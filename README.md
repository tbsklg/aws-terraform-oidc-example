# AWS OIDC example

## Prerequisites

* Terraform v1.2+ installed locally
* AWS account

## Build infrastructure

```
terraform init
terraform apply
```

Add a user to the user pool after the infrastructure is built.

## Retrieve JWT token

```
aws cognito-idp initiate-auth \
    -- auth-flow USER_PASSWORD_AUTH \
    -- client-id $(terrform output -raw user_pool_client_id) \
    -- auth-parameters USERNAME=<username>,PASSWORD=<password>
```

## Call endpoint with JWT token

```
curl -H "Authorization: <access-token>" $(terraform output -raw base_url)/hello
```

You should see the following response:

```
{"message":"Hello, World!"}
```

## Destroy infrastructure

```
terraform destroy
```