# Terraform Plan For Microservices Deployment With AWS ECS

Make sure we have the AWS authentication in place with ~/.aws/credentials to access necessary services on AWS.

Execute terraform planning before applying to the real setup.

```
$ terraform plan
```
Apply instruction to build the setup on AWS infastructure as per the instructions on the terraform.

```
$ terraform apply
```
Destroy the setup if there is any need.

```
$ terraform destroy
```



