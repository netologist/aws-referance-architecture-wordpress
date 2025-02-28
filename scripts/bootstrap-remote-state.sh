#!/bin/sh

## if you use terragrunt, 
## terragrunt support built-in this feature via remote_state 
## (ref: https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#remote_state)
## 
## remote_state {
##   backend = "s3"
##   config = {
##     encrypt        = true
##     bucket         = "hozgans-aws-terraform-states"
##     key            = "${path_relative_to_include()}/terraform.tfstate"
##     region         = "us-east-1"
##     dynamodb_table = "hozgans-aws-lock-table"
##   }
##   generate = {
##     path      = "backend.tf"
##     if_exists = "overwrite_terragrunt"
##   }
## }
## 
## 
## terraform backend example
## 
## Generated by Terragrunt. Sig: nIlQXj57tbuaRZEa
## terraform {
##   backend "s3" {
##     bucket         = "hozgans-aws-terraform-states"
##     dynamodb_table = "hozgans-aws-lock-table"
##     encrypt        = true
##     key            = "blog/terraform.tfstate"
##     region         = "us-east-1"
##   }
## }

export TF_BOOTSTRAP_REGION=us-east-1
export TF_BOOTSTRAP_BUCKET_NAME=hozgans-terraform-bucket-for-remote-states
export TF_BOOTSTRAP_TABLE_NAME=hozgans-terraform-table-for-lock
export TF_BOOTSTRAP_ACCOUNT_NUMBER=$(aws sts get-caller-identity | jq -r .Account)
export TF_BOOTSTRAP_POLICY_NAME=hozgans-terraform-state-policy
export TF_BOOTSTRAP_POLICY_PATH=/tmp/terraform-policy-for-bucket-and-table.json
export TF_BOOTSTRAP_POLICY=$(cat <<-POLICY_FILE
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "hozgansTerraformStatePolicy",
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
                "dynamodb:GetItem"
            ],
            "Resource": "arn:aws:dynamodb:${TF_BOOTSTRAP_REGION}:${TF_BOOTSTRAP_ACCOUNT_NUMBER}:table/${TF_BOOTSTRAP_TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${TF_BOOTSTRAP_BUCKET_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${TF_BOOTSTRAP_BUCKET_NAME}/*"
        }
    ]
}
POLICY_FILE
)

clean_output_files() {
    rm output-tf-s3.json
    rm output-tf-dynamodb.json
    rm output-tf-policy.json
}

create_terraform_state_bucket_and_table() {
    # s3 terraform state files bucket
    aws s3api create-bucket --bucket $TF_BOOTSTRAP_BUCKET_NAME --region $TF_BOOTSTRAP_REGION > output-tf-s3.json # --create-bucket-configuration LocationConstraint=$TF_BOOTSTRAP_REGION
    
    aws s3api put-bucket-encryption --bucket $TF_BOOTSTRAP_BUCKET_NAME --server-side-encryption-configuration "{\"Rules\": [{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\": \"AES256\"}}]}"

    # dynamodb terraform lock table    
    aws dynamodb create-table --region $TF_BOOTSTRAP_REGION --table-name $TF_BOOTSTRAP_TABLE_NAME --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 > output-tf-dynamodb.json 

    # iam policy
    echo $TF_BOOTSTRAP_POLICY > $TF_BOOTSTRAP_POLICY_PATH
    aws iam create-policy --policy-name $TF_BOOTSTRAP_POLICY_NAME --policy-document "file://$TF_BOOTSTRAP_POLICY_PATH" > output-tf-policy.json
}


delete_terraform_state_bucket_and_table() {
    aws s3api delete-bucket --bucket $TF_BOOTSTRAP_BUCKET_NAME --region $TF_BOOTSTRAP_REGION > /dev/null
    aws dynamodb delete-table --table-name $TF_BOOTSTRAP_TABLE_NAME --region $TF_BOOTSTRAP_REGION > /dev/null
    aws iam delete-policy --policy-arn "arn:aws:iam::$TF_BOOTSTRAP_ACCOUNT_NUMBER:policy/$TF_BOOTSTRAP_POLICY_NAME" > /dev/null
}


case $1 in
  clean)
    clean_output_files
    ;;
  install)
    create_terraform_state_bucket_and_table
    ;;
  uninstall)
    delete_terraform_state_bucket_and_table
    ;;
  "")
    echo "please use install or uninstall commands"
    ;;
esac
