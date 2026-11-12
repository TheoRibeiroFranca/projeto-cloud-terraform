# projeto-cloud-terraform

Infraestrutura do Cirro Livros (ConvCommerce) em São Paulo (`sa-east-1`), toda
em código. O ambiente de Ohio (`us-east-2`) foi criado à mão e não é gerido
por este repositório.

## Estrutura

| Diretório    | O que faz                                                    | Onde fica o state       |
| ------------ | ------------------------------------------------------------ | ----------------------- |
| `bootstrap/` | Cria o bucket S3 que guarda o state do `infra/`. Roda uma vez. | Local (não vai pro Git) |
| `infra/`     | O ambiente inteiro: rede, ECS, ALB, RDS, filas, alarmes.     | Bucket S3, com trava    |
| `modules/`   | Módulos reutilizados pelo `infra/`.                          | -                       |

## Pré-requisitos

- Terraform 1.11 ou mais novo
- AWS CLI v2 com o perfil de administrador (SSO). O grupo `convcommerce-devs`
  não tem permissão para criar infraestrutura.

```bash
aws sso login --profile <perfil-admin>
export AWS_PROFILE=<perfil-admin>
aws sts get-caller-identity
```

## Primeira vez: criar o bucket do state

```bash
cd bootstrap
terraform init
terraform apply
terraform output -raw backend_hcl > ../infra/backend.hcl
```

O state do bootstrap fica só na máquina de quem rodou. Se ele se perder, o
bucket continua existindo e pode ser trazido de volta com `terraform import`.

## Subir e destruir o ambiente

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # opcional
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
terraform destroy
```

## Convenções

- Recursos levam o prefixo `convcommerce-sp`. IAM é global na conta, e o
  prefixo `convcommerce-prod` já é usado em Ohio.
- Nada fixo de região: zonas, AMIs e ARNs vêm de variáveis ou data sources.
- Segredos nunca entram no código nem em `.tfvars` commitados.
- Antes de commitar: `terraform fmt -recursive` e `terraform validate`.
- Mudanças entram por branch e pull request, com commits pequenos.
