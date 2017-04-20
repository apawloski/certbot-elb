#! /bin/bash

# There are Let's Encrypt API limits!

DOMAIN="$1"
EMAIL="$2"

# Not sure what to do with these yet
ALB_NAME="$3"
HTTPS_LISTENER_ARN="$4"

# Check inputs. Or something.

# Expects to find the PKI components at /etc/letsencrypt/live/$DOMAIN/
function upload_cert_to_aws {
  # Ugly way to get AWS-name-friendly string of expiration date
  exp_date=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/cert.pem | cut -f2 -d= | awk -v OFS='-' '$1=$1' | cut -f1,2,4 -d-)
  cert_aws_name="${DOMAIN}-until-${exp_date}"

  # Upload to cert to AWS
  export cert_arn=$(aws iam upload-server-certificate  --server-certificate-name "$cert_aws_name" \
                                     --certificate-body file:///etc/letsencrypt/live/$DOMAIN/cert.pem  \
                                     --certificate-chain file:///etc/letsencrypt/live/$DOMAIN/chain.pem \
                                     --private-key file:///etc/letsencrypt/live/$DOMAIN/privkey.pem \
                                     | jq '.ServerCertificateMetadata.Arn')
}

function update_alb {

  aws elbv2 modify-listener --listener-arn "$HTTPS_LISTENER_ARN" \
                            --certificates "$cert_arn"

  if [ $? ] ; then
    echo "Something went wrong when trying to update the HTTPS listener ("$HTTPS_LISTENER_ARN") with new cert ($cert_arn)."
  else
    echo "Updated HTTPS listener successfully."
  fi
}

#
function attempt_cert_create {
  # Create a new cert
  # This returns 0 when a cert is created, but also if the current cert is not up for renewal
  certbot certonly --standalone \
                   --keep-until-expiring \
                   --email $EMAIL \
                   -d $DOMAIN \
                   --test-cert \
                   --agree-tos \
                   -n \
                   --preferred-challenges http

  if [ $? ] ; then
    echo "Something went wrong when trying to create cert for $DOMAIN."
  fi
}

#
function main {
  attempt_cert_create

  # Certbot ran succesfully. Was anything created?
  if [ -e /etc/letsencrypt/live/$DOMAIN/cert.pem ]; then
      echo "New certificate created for $DOMAIN. This is where we might update a load balancer."
      upload_cert_to_aws
#    update_alb
  else
    echo "Certbot ran succesfully, but no certificate generated for $DOMAIN. Probably because the cert was not yet ready for renewal."
  fi
}

main
