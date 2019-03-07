# makefile for automating service deployment

# Load env vars
include .env
VARS:=$(shell sed -ne 's/ *\#.*$$//; /./ s/=.*$$// p' .env )
$(foreach v,$(VARS),$(eval $(shell echo export $(v)="$($(v))")))

.PHONY: profile-create
profile-create:
	aws cloudformation create-stack --stack-name $(SERVICE_PROFILE_NAME) \
									--region $(SERVICE_REGION) \
									--template-body file://$(SERVICE_PROFILE_FILE_PATH) \
									--parameters ParameterKey=InstanceProfileName,ParameterValue=$(SERVICE_PROFILE_NAME) \
									--capabilities CAPABILITY_NAMED_IAM
	aws cloudformation wait stack-create-complete --stack-name $(SERVICE_PROFILE_NAME) \
										 		  --region $(SERVICE_REGION)
	echo "elasticbeanstalk-locust-role stack created..."

.PHONY: profile-delete
profile-delete:
	aws cloudformation delete-stack --stack-name $(SERVICE_PROFILE_NAME) \
									--region $(SERVICE_REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(SERVICE_PROFILE_NAME) \
												  --region $(SERVICE_REGION)
	echo "elasticbeanstalk-locust-role stack deleted..."

.PHONY: profile-check
profile-check:
	aws iam get-instance-profile --instance-profile-name $(SERVICE_PROFILE_NAME) 1>/dev/null

.PHONY: eb-init
eb-init:
	eb init -r $(SERVICE_REGION) -p "Java 8"

.PHONY: eb-deploy
eb-deploy: profile-check eb-init
	eb create --instance_type $(SERVICE_INSTANCE_TYPE) \
			  --scale $(SERVICE_SCALE) \
			  --instance_profile $(SERVICE_PROFILE_NAME) \
			  --cname $(SERVICE_CNAME) \
			  --branch_default $(SERVICE_ENV) \
			  --vpc.id $(SERVICE_VPC) \
			  --vpc.ec2subnets $(SERVICE_EC2_SUBNETS) \
			  --vpc.elbsubnets $(SERVICE_ELB_SUBNETS) \
			  --vpc.elbpublic --vpc.publicip \
			  --envvars TARGET_URL=$(LOCUST_TARGET_URL) \
			  --region $(SERVICE_REGION)

.PHONY: eb-update
eb-update:
	eb setenv TARGET_URL=$(LOCUST_TARGET_URL)
	eb scale $(SERVICE_SCALE)
	eb deploy --staged

.PHONY: eb-terminate
eb-terminate:
	eb terminate --all --force

.PHONY: terminate-all
terminate-all: eb-terminate profile-delete
