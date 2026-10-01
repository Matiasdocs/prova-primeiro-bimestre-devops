data "aws_caller_identity" "current" {}

locals {
  bucket_name = "technova-reservas-tfstate-${data.aws_caller_identity.current.account_id}-us-east-1"
}

resource "terraform_data" "state_bucket" {
  input = local.bucket_name

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      set -euo pipefail

      BUCKET='${self.input}'
      REGION='us-east-1'

      if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
        aws s3api create-bucket \
          --bucket "$BUCKET" \
          --region "$REGION"
      fi

      aws s3api put-bucket-versioning \
        --bucket "$BUCKET" \
        --versioning-configuration Status=Enabled

      aws s3api put-bucket-encryption \
        --bucket "$BUCKET" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

      aws s3api put-public-access-block \
        --bucket "$BUCKET" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

      aws s3api put-bucket-tagging \
        --bucket "$BUCKET" \
        --tagging 'TagSet=[{Key=Name,Value=technova-reservas-tfstate},{Key=Project,Value=technova-reservas},{Key=Environment,Value=learner-lab},{Key=ManagedBy,Value=terraform}]'

      POLICY_JSON="$(
        BUCKET="$BUCKET" python3 -c 'import json,os; b=os.environ["BUCKET"]; print(json.dumps({"Version":"2012-10-17","Statement":[{"Sid":"DenyInsecureTransport","Effect":"Deny","Principal":"*","Action":"s3:*","Resource":["arn:aws:s3:::"+b,"arn:aws:s3:::"+b+"/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}))'
      )"

      aws s3api put-bucket-policy \
        --bucket "$BUCKET" \
        --policy "$POLICY_JSON"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      set -euo pipefail

      BUCKET='${self.input}'

      if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
        DELETE_FILE="$(mktemp)"

        while true; do
          OBJECTS="$(aws s3api list-object-versions \
            --bucket "$BUCKET" \
            --output json)"

          DELETE_PAYLOAD="$(
            printf '%s' "$OBJECTS" | python3 -c 'import json,sys; d=json.load(sys.stdin); items=d.get("Versions",[])+d.get("DeleteMarkers",[]); print(json.dumps({"Objects":[{"Key":x["Key"],"VersionId":x["VersionId"]} for x in items],"Quiet":True}))'
          )"

          COUNT="$(
            printf '%s' "$DELETE_PAYLOAD" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["Objects"]))'
          )"

          if [ "$COUNT" -eq 0 ]; then
            break
          fi

          printf '%s' "$DELETE_PAYLOAD" > "$DELETE_FILE"

          aws s3api delete-objects \
            --bucket "$BUCKET" \
            --delete "file://$DELETE_FILE"
        done

        rm -f "$DELETE_FILE"
        aws s3api delete-bucket --bucket "$BUCKET"
      fi
    EOT
  }
}

resource "aws_dynamodb_table" "locks" {
  name         = "technova-reservas-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = false
  }

  tags = {
    Name = "technova-reservas-tf-locks"
  }
}