# Validação do pacote gerado

- Enunciado oficial lido a partir do arquivo Markdown no repositório do professor.
- Dependências instaladas com `npm ci` a partir do lockfile. Runtime local de verificação: Node 24; a imagem usa Node 22, conforme Dockerfile.
- Sintaxe JavaScript verificada com `node --check`.
- YAML do Compose analisado com parser YAML; isso não equivale a `docker compose config`.
- Shell do deploy e do cloud-init verificado com `bash -n`.
- Terraform formatado e verificado com `terraform fmt -recursive -check` 1.9.8.
- Inicialização dos providers feita sem acesso à conta AWS; arquivos de lock gerados para AWS provider 5.100.0.
- `terraform validate` não pôde ser concluído neste ambiente: o processo do provider não conseguiu inicializar o protocolo de plugin. Execute a validação no seu ambiente, conforme README.
- Nenhum `terraform plan`, `apply` ou `destroy` foi executado contra a AWS.
- Docker não está disponível neste ambiente; build, Compose e integração real com PostgreSQL/RDS ainda dependem da execução pelo aluno.
- Incluído `scripts/smoke-test.py` para verificar o CRUD via HTTP nos dois ambientes e instruções para verificar persistência após reinício.

Não há evidências simuladas nem garantia de nota: permissões efetivas do Lab, execução, commits, relatório e apresentação precisam ser validados pelo aluno.

## Revisão após os seis apontamentos

- README corrigido: DynamoDB locking deprecated, ainda disponível; versão fixada por reprodutibilidade.
- Incluída captura de validate, destroy e histórico Git com tee e pipefail.
- Deploy obrigatório após apply destacado; nenhum deploy foi executado nesta revisão.
- Adicionada lista opcional de IPv4 /32 para acesso à API; não abre SSH nem RDS a esses IPs.
- DynamoDB configurado com AWS-owned key, mantendo criptografia.
- Revisão verificada com terraform fmt e sintaxe Bash dos blocos do README; validação de provider e testes AWS continuam pendentes.
