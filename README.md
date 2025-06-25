python3 -m venv python-env
source python-env/bin/activate
pip install -r python-requirements.txt
./build-sam.sh


sam validate --template template-sam.yaml  --region eu-west-1 --lint


https://github.com/ganshan/sam-dynamodb-local

