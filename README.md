# TechNova — API de Reservas

**Aluno:** Matheus Gabriel Correa Braga Viana

**RA:** 6325053

Projeto para a Prova do Primeiro Bimestre de DevOps, 2026.2.
Node.js/Express com CRUD PostgreSQL, Docker Compose e Terraform modular para AWS Academy Learner Lab.

Enunciado: https://github.com/AleTavares/devops_20262/blob/main/provas/prova-primeiro-bimestre.md

## Arquitetura e escolhas

- Região fixa `us-east-1`; nenhum user, group, role ou instance profile IAM criado.
- EC2 `t2.micro`, Amazon Linux 2023, subnet pública, `LabInstanceProfile` já existente no Lab. Não se cria nem se modifica a `LabRole` associada a esse profile.
- VPC `10.40.0.0/16`, duas AZs, duas subnets públicas e duas privadas.
- EC2: entrada TCP 22 e 3000 do IPv4 público do aluno (/32); `api_extra_cidrs` permite IPs /32 adicionais apenas na porta 3000, com lista vazia por padrão. Saída TCP 80/443 para downloads e 5432 somente para o SG do RDS.
- RDS PostgreSQL 16, `db.t3.micro`, disco criptografado de 20 GB, sem IP público, subnet group privado nas duas AZs. A instância é Single-AZ para economizar; as subnets em duas AZs não significam uma instância Multi-AZ.
- RDS recebe TCP 5432 somente do SG da EC2. `rds.force_ssl=1`; a API valida o certificado com a CA oficial da AWS.
- Subnets privadas sem NAT e sem rota para Internet Gateway.
- Backend separado: S3 privado com versionamento, AES256, política exigindo TLS e DynamoDB com chave `LockID`. O bucket é criado e configurado por `terraform_data` com AWS CLI, porque o Learner Lab bloqueia por SCP a leitura de Object Lock que o recurso `aws_s3_bucket` faz após a criação.
- Terraform 1.9.x (testar com 1.9.8) e AWS provider 5.100.x. Essa faixa é uma escolha de reprodutibilidade do projeto, não uma exigência do enunciado nem uma indicação de que DynamoDB foi removido das versões posteriores. A documentação atual marca o locking DynamoDB como obsoleto (deprecated), ainda disponível, com remoção prevista para uma versão futura. Ele permanece neste projeto por ser exigido pela prova.
- Terraform instala Docker na EC2. O comando `bash scripts/deploy.sh` faz o deploy da API após o apply. O código é transferido por SSH e a imagem é construída na EC2; não depende de GitHub público nem de um registry próprio.
- A senha não é incluída em `user_data` nem impressa por outputs. Ela fica no state Terraform, que deve ser protegido, e em `/opt/reservas/api.env` com permissão 0600 na EC2.
- A API usa o usuário do banco definido no provisionamento, escolha simplificada para este laboratório. Uma implantação de produção deve separar o usuário de migração do usuário de runtime.
- API HTTP sem autenticação, limitada pelo SG aos IPs explicitamente autorizados; utilizar somente dados fictícios da prova. O objetivo aqui é o escopo do exercício.

## Contrato HTTP

| Método | Rota | Resultado |
|---|---|---|
| POST | /reservas | 201 e reserva criada; exige cliente, data e status |
| GET | /reservas | 200 e lista ordenada por id |
| GET | /reservas/:id | 200 ou 404 |
| PUT | /reservas/:id | 200 ou 404; substitui os três campos |
| DELETE | /reservas/:id | 204 ou 404 |
| GET | /health | 200 se PostgreSQL responde; 503 se não responde |

`cliente`: texto de 1 a 150 caracteres. `data`: data real no formato YYYY-MM-DD. `status`: texto de 1 a 50 caracteres. O enunciado não fixa um enum; exemplos utilizados são pendente, confirmada e cancelada. `id`: inteiro gerado pelo PostgreSQL. SQL usa parâmetros, não concatena entrada do usuário.

A tabela é criada com `CREATE TABLE IF NOT EXISTS` na inicialização. Isso atende ao schema inicial do exercício; não substitui migrações versionadas para futuras mudanças de schema.

## Pré-requisitos

Os comandos abaixo usam Bash no Linux/macOS ou WSL2 no Windows. Não cole diretamente no CMD/PowerShell. Necessários: Docker com Compose v2, Terraform 1.9.8, AWS CLI v2, Python 3, curl, tar e OpenSSH. Não precisa instalar Node.js localmente: o build ocorre no Docker.

Antes de qualquer `terraform init`, confira `terraform version`. O projeto exige `>= 1.9.0, < 1.10.0` nos dois diretórios: Terraform 1.10 ou superior será rejeitado pela configuração. Instale a versão 1.9.8 pelo [download oficial](https://releases.hashicorp.com/terraform/1.9.8/) e confira novamente qual executável está no PATH.

Execute tudo a partir da raiz deste projeto. Não há credenciais AWS nos arquivos. Inicie o Learner Lab e configure as três credenciais temporárias mostradas em AWS Details → AWS CLI, incluindo `aws_session_token`, no perfil AWS utilizado pelo terminal. Não use credenciais de outra conta.

```bash
terraform version
mkdir -p evidencias
set -o pipefail
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
aws sts get-caller-identity
docker compose version
```

## 1. Executar localmente

```bash
cp .env.example .env
mkdir -p evidencias
set -o pipefail
docker compose config --quiet
docker compose build 2>&1 | tee evidencias/docker-build.txt
docker compose up -d --wait
docker compose ps | tee evidencias/compose-ps.txt
python3 scripts/smoke-test.py | tee evidencias/crud-local.txt
```

Depois da preparação do `.env`, `docker compose up -d --build --wait` sobe os dois serviços com um comando. O banco não publica 5432 no host. A API local está em http://localhost:3000. A porta do host pode ser alterada por `API_PORT` no `.env`.

A senha do `.env.example` é demonstrativa e exclusiva do ambiente local. Não é uma credencial real e não deve ser usada no RDS. Depois de inicializado o volume, mudar POSTGRES_PASSWORD no Compose não altera automaticamente a senha do usuário já criado no banco.

### Demonstrar persistência local

```bash
curl --fail-with-body -sS -X POST http://localhost:3000/reservas \
  -H 'Content-Type: application/json' \
  -d '{"cliente":"Evidencia de persistencia","data":"2026-10-01","status":"pendente"}'
docker compose down
docker compose up -d --wait
curl --fail-with-body -sS http://localhost:3000/reservas \
  | tee evidencias/persistencia-local.json
docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, cliente, data, status FROM reservas ORDER BY id;"' \
  | tee evidencias/postgresql-local.txt
```

`docker compose down` preserva o volume; `docker compose down -v` apaga os dados.

## 2. Preparar os inputs AWS

Mantenha este terminal aberto até concluir apply, deploy e destroy. As variáveis abaixo são de sessão. Em outro terminal, exporte novamente os mesmos valores; não gere outra senha por acidente.

```bash
mkdir -p .keys
chmod 700 .keys
if [ ! -f .keys/devops ]; then
  ssh-keygen -t ed25519 -f .keys/devops -N '' -C 'technova-learner-lab'
fi
chmod 600 .keys/devops
export TF_VAR_ssh_public_key="$(cat .keys/devops.pub)"
export TF_VAR_access_cidr="$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')/32"
read -r -s -p 'Crie uma senha RDS de 16–64 caracteres (letras, numeros, _ ou -): ' TF_VAR_db_password
printf '\n'
export TF_VAR_db_password
```

Guarde a senha escolhida em um gerenciador de senhas. Não a publique e não execute o deploy com `bash -x`. O Terraform valida o formato do CIDR e da senha. Se seu IP público mudar, atualize `TF_VAR_access_cidr`, revise o plan e aplique antes de acessar novamente a EC2. Por padrão, a API também aceita somente esse IP. Para o professor acessar de outra rede, adicione o IPv4 público real dele na lista opcional abaixo. Não use seu próprio IP como se fosse o dele; confirme qual é a saída pública da rede usada por ele.

```bash
read -r -p 'IPv4 público do professor, sem /32: ' PROFESSOR_IP
export TF_VAR_api_extra_cidrs="$(python3 - "$PROFESSOR_IP" <<'PYIP'
import ipaddress, json, sys
print(json.dumps([str(ipaddress.IPv4Address(sys.argv[1].strip())) + '/32']))
PYIP
)"
```

Faça isso antes do próximo plan/apply. Essa regra adicional libera somente 3000; o SSH continua restrito ao aluno e o RDS ao SG da EC2. Se o professor usar a mesma saída pública já autorizada, a regra duplicada é evitada. Para remover os acessos extras, exporte `TF_VAR_api_extra_cidrs='[]'`, gere um novo plan, revise e aplique.

Para atualizar seu IP, sem precisar de SSH:

```bash
export TF_VAR_access_cidr="$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')/32"
terraform -chdir=infra plan -out=infra.tfplan
terraform -chdir=infra apply infra.tfplan
```

Esses comandos usam as APIs da AWS com suas credenciais do Lab. Mantenha as demais variáveis da sessão, incluindo a lista extra, para preservar os acessos desejados.

## 3. Criar o backend antes da infraestrutura

```bash
terraform -chdir=infra/backend init
terraform -chdir=infra/backend fmt -check
terraform -chdir=infra/backend validate -no-color 2>&1 | tee evidencias/terraform-backend-validate.txt
terraform -chdir=infra/backend plan -out=backend.tfplan
terraform -chdir=infra/backend apply backend.tfplan
STATE_BUCKET="$(terraform -chdir=infra/backend output -raw bucket_name)"
terraform -chdir=infra init -backend-config="bucket=$STATE_BUCKET"
```

O nome do bucket inclui a conta AWS real obtida por `aws_caller_identity`; nenhum nome global fictício precisa ser substituído. A tabela tem o mesmo nome fixo usado no backend principal. Este projeto pressupõe um único ambiente com esses nomes na conta. Se recursos desses nomes já existirem fora deste state, resolva a propriedade/importação antes do apply.

O bucket do backend é criado pela AWS CLI (via `terraform_data` com `local-exec`), então `aws` e `python3` precisam estar no PATH. O bootstrap usa state local e não depende do bucket que está criando. Preserve `infra/backend/terraform.tfstate` com segurança até destruir o backend; não o envie ao Git. O state da infraestrutura principal fica no S3. Módulos filhos herdam o provider AWS com tags padrão. Recursos auxiliares sem suporte a tags, como associações de route table, não recebem tags.

## 4. Validar e provisionar

```bash
terraform -chdir=infra fmt -recursive -check
terraform -chdir=infra validate -no-color 2>&1 | tee evidencias/terraform-validate.txt
terraform -chdir=infra plan -out=infra.tfplan
terraform -chdir=infra show -no-color infra.tfplan > evidencias/terraform-plan.txt
terraform -chdir=infra apply infra.tfplan
terraform -chdir=infra output | tee evidencias/terraform-outputs.txt
```

Revise o plan antes do apply: nenhum recurso IAM, região correta, tipos micro, SG do RDS por referência, RDS privado e criptografado. Não publique os planos binários: eles podem conter a senha. Outputs de texto do plan devem ser inspecionados antes de publicar.

Versione `app/package-lock.json`, `infra/.terraform.lock.hcl` e `infra/backend/.terraform.lock.hcl`. Não versione `.terraform`, `.tfstate`, planos binários, `.env`, chaves nem arquivos de credenciais.

## 5. Fazer deploy e testar na nuvem

Passo obrigatório: o `terraform apply` prepara a infraestrutura e instala Docker, mas não inicia a API. Até executar o deploy abaixo com sucesso, a URL gerada pelo output não responderá.

```bash
bash scripts/deploy.sh
API_URL="$(terraform -chdir=infra output -raw api_url)"
python3 scripts/smoke-test.py "$API_URL" | tee evidencias/crud-aws.txt
curl --fail-with-body -sS "$API_URL/health" | tee evidencias/health-aws.json
```

O script aguarda o SSH e o cloud-init, baixa a CA pública da AWS, transfere código e configuração com SSH, monta o certificado somente para leitura e inicia o container como usuário `node`. O processo principal é reiniciado pelo Docker após reboot da EC2. Arquivos temporários com senha são removidos ao concluir o deploy.

Não há senha em Dockerfile ou na imagem. Administradores da EC2 e do Docker podem acessar as variáveis do container, como esperado neste modelo. `sensitive=true` esconde a senha na apresentação normal do Terraform, mas não a remove do state.

### Demonstrar PostgreSQL e persistência na nuvem

```bash
EC2_IP="$(terraform -chdir=infra output -raw ec2_public_ip)"
curl --fail-with-body -sS -X POST "$API_URL/reservas" \
  -H 'Content-Type: application/json' \
  -d '{"cliente":"Persistencia RDS","data":"2026-10-01","status":"confirmada"}'
ssh -i .keys/devops "ec2-user@$EC2_IP" 'sudo docker restart technova-reservas'
for attempt in $(seq 1 30); do
  if curl --fail --silent "$API_URL/health"; then break; fi
  sleep 2
done
curl --fail-with-body -sS "$API_URL/reservas" | tee evidencias/persistencia-rds.json
ssh -i .keys/devops "ec2-user@$EC2_IP" 'sudo docker ps' | tee evidencias/docker-aws.txt
```

Capturas do console AWS (subnets privadas, regra TCP 5432 com origem no SG da EC2, RDS privado e criptografado, versionamento/criptografia do S3 e tabela DynamoDB) complementam as evidências em texto. O retorno de /health verifica conexão ao banco; o CRUD e a leitura após reinício demonstram o comportamento completo.

### Diagnóstico

```bash
EC2_IP="$(terraform -chdir=infra output -raw ec2_public_ip)"
ssh -i .keys/devops "ec2-user@$EC2_IP" 'sudo cloud-init status --long'
ssh -i .keys/devops "ec2-user@$EC2_IP" 'sudo tail -n 100 /var/log/cloud-init-output.log'
ssh -i .keys/devops "ec2-user@$EC2_IP" 'sudo docker logs --tail 100 technova-reservas'
```

`ExpiredToken`: renove as credenciais e o session token do Lab. Falha no SSH: confira /32 atual, chave e status da EC2. Falha TLS: confira a CA e use o hostname RDS, não um IP. `apply` concluir não significa que cloud-init e deploy já concluíram; execute o script. O PostgreSQL deve estar acessível somente da EC2, não diretamente do seu notebook.

## 6. Destruir após as evidências

Os comandos abaixo apagam os recursos e os dados do laboratório. Este RDS está configurado sem snapshot final e sem backups para o exercício descartável. Execute somente depois de salvar suas evidências e o que precisar dos dados.

```bash
mkdir -p evidencias
set -o pipefail
if terraform -chdir=infra destroy -no-color 2>&1 | tee evidencias/terraform-destroy.txt; then
  terraform -chdir=infra/backend destroy -no-color 2>&1 | tee evidencias/terraform-backend-destroy.txt
else
  printf 'Destroy da infraestrutura falhou ou foi cancelado; backend preservado.\n' >&2
fi
# Limpeza local, opcional; -v apaga o banco local.
docker compose down -v
unset TF_VAR_db_password
```

O backend deve ser destruído por último, pois a infraestrutura principal depende dele para ler o state e realizar locking. No destroy do backend, um script (`local-exec`) apaga todas as versões e delete markers do bucket antes de removê-lo; o bucket de state é versionado e `aws s3 rb` não remove versões antigas. Não reutilize essa configuração destrutiva de backend em produção.

## 7. Registrar o histórico Git

Depois dos commits e do merge, registre o histórico:

```bash
mkdir -p evidencias
set -o pipefail
git --no-pager log --oneline --graph --decorate --all 2>&1 | tee evidencias/git-log.txt
git --no-pager log --merges --oneline --all 2>&1 | tee evidencias/git-merges.txt
```

O gráfico mostra o commit de merge da feature branch. O arquivo do histórico é uma fotografia anterior ao commit que adiciona a própria evidência; o repositório contém o histórico final.

`tee` salva a saída, mas um arquivo existente não prova sucesso. Confira o resultado de validate e destroy. `set -o pipefail` mantém a falha do comando original mesmo com `tee`; em um terminal interativo, pare e corrija qualquer erro antes de continuar.

## Criptografia DynamoDB e fontes técnicas

No provider AWS 5.100.0, `server_side_encryption.enabled = true` seleciona uma chave gerenciada pela AWS quando nenhum `kms_key_arn` é informado. `enabled = false`, usado neste projeto, seleciona uma chave de propriedade da AWS (AWS-owned key). Isso não desliga a criptografia: todas as tabelas DynamoDB permanecem criptografadas em repouso. A chave padrão AWS-owned não exige autorização adicional para seu uso pelo DynamoDB.

Uma falha de apply não comprova, por si só, um problema de KMS. Leia a ação/recurso no erro: credenciais expiradas, permissões DynamoDB/S3 ou outras restrições também podem causar falha. Essa configuração evita uma dependência desnecessária de autorização da chave, sem garantir permissões efetivas no Learner Lab.

- [Terraform: backend S3 e locking DynamoDB deprecated](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Provider AWS 5.100.0: aws_dynamodb_table](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/dynamodb_table)
- [AWS: criptografia e autorização de chaves do DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/encryption.usagenotes.html)
