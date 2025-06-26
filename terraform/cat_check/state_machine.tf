resource "aws_iam_role" "sfn_role" {
  name = "CatDetectionSFNRole"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Effect : "Allow",
      Principal : { Service : "states.amazonaws.com" },
      Action : "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sfn_policy" {
  name = "CatDetectionPermissions"
  role = aws_iam_role.sfn_role.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : ["rekognition:DetectLabels"],
        Resource : "*" # Rekognition doesn’t support resource-level perms
      },
      {
        Effect : "Allow",
        Action : ["dynamodb:UpdateItem"],
        Resource : aws_dynamodb_table.cat_status.arn # limit to our table
      },
      {
        "Effect" : "Allow",
        "Action" : "s3:GetObject",
        "Resource" : "${module.uploads_bucket.s3_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_sfn_state_machine" "cat_detection" {
  name     = "CatDetectionFlow"
  role_arn = aws_iam_role.sfn_role.arn

  definition = jsonencode({
    Comment : "Detect whether an uploaded image contains a cat and record the result.",
    StartAt : "TouchDynamoDB",
    States : {
      TouchDynamoDB : {
        Type : "Task",
        Resource : "arn:aws:states:::aws-sdk:dynamodb:updateItem",
        Parameters : {
          TableName : "${aws_dynamodb_table.cat_status.name}",

          Key : {
            "pic_id" : { "S.$" : "$.detail.object.key" }
          },

          UpdateExpression : "SET #c = :iscat, #s = :state, #t = :timestamp",
          ExpressionAttributeNames : {
            "#c" : "isCat",
            "#s" : "status",
            "#t" : "TimeToExist"
          },
          ExpressionAttributeValues : {
            ":iscat" : { "Bool" : "False" },
            ":state" : { "S" : "processing" },
            ":timestamp" : { "S" : "States.Format('{}',States.MathAdd($.detail.metadata.created_at, 300))" }
          }
        },
        ResultPath : null,
        Next : "DetectLabels"
      }
      DetectLabels : {
        Type : "Task",
        Resource : "arn:aws:states:::aws-sdk:rekognition:detectLabels",
        Parameters : {
          Image : {
            S3Object : {
              "Bucket.$" : "$.detail.bucket.name",
              "Name.$" : "$.detail.object.key"
            }
          },
          MaxLabels : 10,
          MinConfidence : 80
        },
        ResultPath : "$.rekognition",
        Next : "DetermineIsCat"
      },

      # Use an intrinsic to calculate a Boolean
      DetermineIsCat : {
        Type : "Pass",
        Parameters : {
          "bucket.$" : "$.detail.bucket.name",
          "key.$" : "$.detail.object.key",
          # true if *any* label name == "Cat"
          "isCat.$" : "States.ArrayContains($.rekognition.Labels[*].Name, 'Cat')"
        },
        ResultPath : "$.decision",
        Next : "UpdateDynamoDB"
      },

      UpdateDynamoDB : {
        Type : "Task",
        Resource : "arn:aws:states:::aws-sdk:dynamodb:updateItem",
        Parameters : {
          TableName : "${aws_dynamodb_table.cat_status.name}",
          Key : {
            "pic_id" : { "S.$" : "$.decision.key" }
          },

          UpdateExpression : "SET #c = :iscat, #s = :state",
          ExpressionAttributeNames : {
            "#c" : "isCat",
            "#s" : "status"
          },
          ExpressionAttributeValues : {
            ":iscat" : { "Bool.$" : "$.decision.isCat" },
            ":state" : { "S" : "processed" }
          },
          ReturnValues : "NONE"
        },
        End : true
      }
    }
  })
}

resource "aws_cloudwatch_event_rule" "s3_object_create" {
  name = "InvokeCatDetectionOnUpload"
  event_pattern = jsonencode({
    "source" : ["aws.s3"],
    "detail-type" : ["Object Created"],
    "detail" : {
      "bucket" : { "name" : [module.uploads_bucket.s3_bucket_id] }
    }
  })
}

resource "aws_iam_role" "events_to_sfn" {
  name = "EventBridgeToSFNRole"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Effect : "Allow",
      Principal : { Service : "events.amazonaws.com" },
      Action : "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "events_to_sfn_attach" {
  role       = aws_iam_role.events_to_sfn.name
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
}

resource "aws_cloudwatch_event_target" "start_state_machine" {
  rule     = aws_cloudwatch_event_rule.s3_object_create.name
  arn      = aws_sfn_state_machine.cat_detection.arn
  role_arn = aws_iam_role.events_to_sfn.arn
}
