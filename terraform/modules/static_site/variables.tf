variable "bucket_name" {
  description = "Globally unique bucket name for the static site"
  type        = string
}

variable "api_base_url" {
  description = "Base URL (or relative path) of the backend API"
  type        = string
}

variable "content_dir" {
  description = "Directory containing the built/static assets to upload"
  type        = string
}

variable "index_document" {
  type        = string
  default     = "index.html"
}

variable "error_document" {
  type        = string
  default     = "error.html"
}