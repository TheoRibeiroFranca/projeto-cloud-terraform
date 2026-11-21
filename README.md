# projeto-cloud-terraform

Infraestrutura do Cirro Livros (ConvCommerce) em São Paulo (`sa-east-1`), toda
em código. O ambiente de Ohio (`us-east-2`) foi criado à mão e não é gerido
por este repositório.

## Repositórios do projeto

| Repositório | Serviço ECS | Responsabilidade |
| ----------- | ----------- | ---------------- |
| [projeto-cloud-backend](https://github.com/PedroMRegis/projeto-cloud-backend) | `backend-api`, `order-worker` | Catálogo, contas, cotação, pedido. Tem também os scripts da etapa manual em Ohio |
| [projeto-cloud-chatbot](https://github.com/PedroMRegis/projeto-cloud-chatbot) | `chatbot` | Vendedor conversacional |
| [projeto-cloud-frontend](https://github.com/PedroMRegis/projeto-cloud-frontend) | `frontend` | Loja em React |
| **projeto-cloud-terraform** (este) | - | Infraestrutura de São Paulo |

O `apply` constrói as imagens a partir do código desses três repositórios
(`infra/images.tf`). Por padrão, eles ficam ao lado deste, na mesma pasta
(`var.app_source_dir`):

```
cloud/
├── projeto-cloud-backend/
├── projeto-cloud-chatbot/
├── projeto-cloud-frontend/
└── projeto-cloud-terraform/
```

## Estrutura

| Diretório    | O que faz                                                    | Onde fica o state       |
| ------------ | ------------------------------------------------------------ | ----------------------- |
| `bootstrap/` | Cria o bucket S3 que guarda o state do `infra/`. Roda uma vez. | Local (não vai pro Git) |
| `infra/`     | O ambiente inteiro: rede, ECS, ALB, RDS, filas, alarmes.     | Bucket S3, com trava    |
| `modules/`   | Módulos reutilizados pelo `infra/`.                          | -                       |
| `scripts/`   | Envio das imagens, task avulsa, conta de admin e verificação de portabilidade. O `apply` chama os três primeiros. | - |

Além do ambiente, o `apply` cria um orçamento mensal da região
(`var.monthly_budget_usd`, US$ 100 por padrão), com avisos e alarmes para os
e-mails de `var.alarm_emails`, e a conta de administrador da loja
(`var.admin_email`), com a senha gerada e guardada só no Parameter Store.

`scripts/check-portability.sh` comprova que o ambiente não depende de Ohio e,
com `--destroyed`, que o `destroy` não deixou nada para trás.

## Pré-requisitos

- Terraform 1.11 ou mais novo
- Docker em execução e Git Bash (no Windows), para construir as imagens
- Os três repositórios de aplicação clonados ao lado deste
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
