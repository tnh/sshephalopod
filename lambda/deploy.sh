#!/bin/bash

if [ $# -ne 6 ]; then
    echo $#
    echo "usage: $0 <config-bucket> <zipfile> <idp-metadata-url> <dns-domain> <keypair-bucket> <keypair-name>"
    exit 1
fi

LAMBDA_STACK="${LAMBDA_STACK:-sshephalopod}"

BUCKET=$1
ZIPFILE=$2
IDP_METADATA=$3
DNSDOMAIN=$4
KP_BUCKET=$5
KP_NAME=$6

log () {
    date "+%Y-%m-%d %H:%M:%S $1"
}

die () {
    echo "FATAL: $1"
    exit 1
}

wait_completion () {
    local STACK=$1
    echo -n "Waiting for stack $STACK to complete:"
    while true; do
        local STATUS=$( aws cloudformation describe-stack-events \
            --stack-name $STACK \
            --query 'StackEvents[].{x: ResourceStatus, y: ResourceType}' \
            --output text | \
            grep "AWS::CloudFormation::Stack" | head -n 1 | awk '{ print $1 }'
        )
        case $STATUS in
            UPDATE_COMPLETE_CLEANUP_IN_PROGRESS)    : ;;
            UPDATE_COMPLETE|CREATE_COMPLETE)
                echo "stack $STACK complete"
                return 0 ;;
            *ROLLBACK*)
                echo "stack $STACK rolling back"
                return 1 ;;
            FAILED)
                echo "ERROR updating stack"
                return 1 ;;
            "")
                echo "No output while looking for stack completion"
                return 1 ;;
            *) : ;;
        esac
        echo -n "."
        sleep 5
    done
}

create_lambda_stack () {
    local STACK=$1
    local BUCKET=$2
    log "Creating stack $STACK"
    local OUT=$( aws cloudformation create-stack \
        --stack-name $LAMBDA_STACK \
        --capabilities CAPABILITY_IAM \
        --template-body file://sshephalopod.json \
        --parameters \
            "ParameterKey=Bucket,ParameterValue=$BUCKET" \
            "ParameterKey=CodeFile,ParameterValue=$ZIPFILE" \
            "ParameterKey=IdpMetadataEndpoint,ParameterValue=$IDP_METADATA" \
            "ParameterKey=DNSDomain,ParameterValue=$DNSDOMAIN" \
            "ParameterKey=CAKeyPairBucket,ParameterValue=$KP_BUCKET" \
            "ParameterKey=CAKeyPairKeyname,ParameterValue=$KP_NAME"

    )
    wait_completion $STACK || return 1
}

update_lambda_stack () {
    local STACK=$1
    local BUCKET=$2
    log "Updating stack $STACK"
    local OUT=$( aws cloudformation update-stack \
        --stack-name $LAMBDA_STACK \
        --capabilities CAPABILITY_IAM \
        --template-body file://sshephalopod.json \
        --parameters \
            "ParameterKey=Bucket,ParameterValue=$BUCKET" \
            "ParameterKey=CodeFile,ParameterValue=$ZIPFILE" \
            "ParameterKey=IdpMetadataEndpoint,ParameterValue=$IDP_METADATA" \
            "ParameterKey=DNSDomain,ParameterValue=$DNSDOMAIN" \
            "ParameterKey=CAKeyPairBucket,ParameterValue=$KP_BUCKET" \
            "ParameterKey=CAKeyPairKeyname,ParameterValue=$KP_NAME"
    )
    wait_completion $STACK || return 1
}

# Create the stack of the Lambda function
if [ -z "$( aws cloudformation describe-stacks --stack-name $LAMBDA_STACK 2>/dev/null )" ]; then
    create_lambda_stack $LAMBDA_STACK $BUCKET || die "Can't create stack"
else
    update_lambda_stack $LAMBDA_STACK $BUCKET || die "Can't update stack"
fi

log "Complete"
