# Relatório do Processo — Prova do Primeiro Bimestre de DevOps

**Aluno:** Matheus Gabriel Correa Braga Viana  
**RA:** 6325053  
**Data da prova:** 01/10/2026  
**Ferramenta de IA utilizada:** ChatGPT  
**Repositório:** https://github.com/Matiasdocs/prova-primeiro-bimestre-devops

> Rascunho estruturado para revisão do aluno. Complete cada resposta em formato dissertativo, com pelo menos dez linhas por questão. Os textos iniciais usam os registros da execução compartilhados no chat; acrescente somente experiências reais e remova esta observação antes da entrega.

## Questão 1 — A Jornada Completa (Aulas 01 a 07)

**Pergunta:** Como você conectou Git, Docker, Docker Compose, Terraform, módulos e remote state? Explique a ordem seguida e a relação com as aulas.

### Texto inicial

Organizei o projeto da API de Reservas em um repositório próprio, com commits separados para a aplicação, o ambiente local, a infraestrutura e os scripts. Utilizei a branch `feat/prova-devops`, integrada à `main` por um commit de merge. A aplicação utiliza Node.js/Express e PostgreSQL para criar, consultar, atualizar e excluir reservas.

O ambiente local foi organizado com Docker e Docker Compose. Depois, provisionei a infraestrutura na AWS com Terraform e módulos para VPC, Security Groups, EC2 e RDS. O backend de state foi preparado antes da infraestrutura principal, utilizando S3 e DynamoDB. Após o provisionamento, executei `scripts/deploy.sh` e os testes da API na nuvem.

Salvei evidências dos testes e das configurações no console AWS. Ao concluir, destruí primeiro os recursos da aplicação e depois o backend, preservando os logs na pasta `evidencias`.

### Desenvolver antes de entregar

- Explique por que testou localmente antes de provisionar na AWS.
- Relacione a Aula 01 ao Git/Docker, a Aula 02 ao Compose, as Aulas 03 a 06 à infraestrutura e a Aula 07 ao uso crítico de IA.
- Explique uma ligação concreta entre output e input dos módulos do seu código.
- Diferencie o que o `terraform apply` prepara do que o script de deploy executa.
- Transforme estes pontos em parágrafos e confira o mínimo de dez linhas.

## Questão 2 — O Processo com IA como Copiloto

**Pergunta:** Qual ferramenta utilizou, quais foram os prompts principais, o que funcionou e o que precisou corrigir? Compare com fazer manualmente.

### Texto inicial

Utilizei o ChatGPT como apoio para estruturar os arquivos do projeto e orientar a execução dos comandos. No pedido inicial, destaquei que o ambiente era o AWS Academy Learner Lab e que a solução deveria utilizar os recursos de IAM existentes, sem criar usuários, grupos ou roles. Também solicitei os arquivos completos e executei os comandos no meu ambiente.

Durante a execução, compartilhei saídas do terminal e capturas do console para conferir os resultados. Houve uma adaptação do bootstrap do backend, registrada no commit `fix: adapta bootstrap do backend ao Learner Lab`. Na versão final, o bucket foi configurado por comandos da AWS CLI executados pelo Terraform.

O apoio também foi usado para conferir os testes de CRUD, reunir evidências e orientar a destruição na ordem correta. Ao retomar o trabalho em outra conversa, foi necessário recuperar o contexto e conferir o histórico dos comandos para identificar as etapas já executadas.

### Desenvolver antes de entregar

- Acrescente exemplos dos seus prompts, identificando se são transcrições ou resumos.
- Descreva qual parte gerada economizou mais tempo para você e por quê.
- Explique a dificuldade real que levou à adaptação do backend, consultando o erro original; não presuma a causa.
- Conte onde a IA atrapalhou ou precisou de correção, com um exemplo verdadeiro.
- Compare esse processo com o que você precisaria fazer manualmente.
- Não descreva um fluxo Kiro Spec: a ferramenta informada neste rascunho é o ChatGPT.
- Transforme os pontos em parágrafos e confira o mínimo de dez linhas.

## Questão 3 — Infraestrutura, Segurança e o Learner Lab

**Pergunta:** Explique a arquitetura, a separação entre EC2 pública e RDS privado, o uso de LabRole/LabInstanceProfile e as restrições do Lab.

### Texto inicial

A infraestrutura foi provisionada em `us-east-1`, com uma VPC e subnets públicas e privadas distribuídas em duas zonas de disponibilidade. A EC2 `t2.micro` ficou em uma subnet pública para permitir o acesso autorizado à API e ao SSH. O RDS PostgreSQL `db.t3.micro` ficou nas subnets privadas, sem acesso público e com armazenamento criptografado.

O Security Group do banco permite a porta 5432 somente a partir do Security Group da EC2. Assim, o acesso ao PostgreSQL acontece pela aplicação, sem expor diretamente o banco à internet. As portas 22 e 3000 da EC2 foram restritas aos endereços autorizados na configuração do projeto.

Utilizei o `LabInstanceProfile` existente, associado à `LabRole`, sem criar recursos próprios de IAM. O backend utilizou S3 com versionamento, criptografia e bloqueio de acesso público, além da tabela DynamoDB `technova-reservas-tf-locks`, com chave `LockID`. O bootstrap do backend manteve seu próprio state local.

### Desenvolver antes de entregar

- Explique como configurou as credenciais temporárias e o Session Token, sem incluir seus valores.
- Relate quais restrições do Lab realmente encontrou durante a execução.
- Explique a diferença entre subnets em duas AZs e uma instância RDS Multi-AZ.
- Explique por que o backend é criado primeiro e removido por último.
- Descreva a conexão da API ao RDS com TLS e a validação do certificado presentes no projeto.
- Transforme os pontos em parágrafos e confira o mínimo de dez linhas.

## Questão 4 — Validação e Responsabilidade

**Pergunta:** Qual checklist aplicou antes do apply, como validou segurança e funcionamento, e quais são os riscos de aceitar código de IA sem revisão?

### Texto inicial

Registrei arquivos de validação do Terraform e do plano de execução na pasta `evidencias`. Na AWS, conferi configurações de rede, regras de Security Groups, acesso público e criptografia do RDS, além do versionamento e da proteção do S3. Essas verificações foram acompanhadas por capturas do console.

O health check retornou `{"status":"ok","database":"ok"}`. Os testes automatizados verificaram criação, leitura, atualização e exclusão de reservas, além de respostas para entradas inválidas e registros inexistentes. Para verificar a persistência, criei a reserva de ID 2, executei novamente o deploy que remove e recria o contêiner e consultei o mesmo registro no RDS.

Ao terminar, executei a destruição da infraestrutura principal, com 25 recursos removidos, e depois a destruição do backend, com dois recursos Terraform removidos. As saídas foram salvas com `tee`. O projeto também possui regras no `.gitignore` para evitar o versionamento de arquivos de state, variáveis, chaves e configurações locais com segredos.

### Desenvolver antes de entregar

- Descreva apenas as verificações que realmente realizou antes do `apply`, distinguindo-as das verificações posteriores.
- Confira e explique o resultado de `terraform validate` e o conteúdo do plano salvo.
- Explique riscos concretos de código não revisado: banco público, permissões excessivas, segredos versionados e custos.
- Relacione histórico Git, isolamento em contêineres e plano Terraform à possibilidade de revisar e testar mudanças.
- Explique por que um arquivo de log existente não basta: é necessário conferir o resultado da operação.
- Transforme os pontos em parágrafos e confira o mínimo de dez linhas.

## Referências às evidências

- [Histórico Git](evidencias/git-log.txt) e [merges](evidencias/git-merges.txt)
- [Build Docker](evidencias/docker-build.txt) e [Docker Compose](evidencias/compose-ps.txt)
- [CRUD local](evidencias/crud-local.txt) e [persistência local](evidencias/persistencia-local.json)
- [Validação Terraform](evidencias/terraform-validate.txt) e [plano](evidencias/terraform-plan.txt)
- [Deploy na AWS](evidencias/docker-aws.txt), [CRUD AWS](evidencias/crud-aws.txt) e [health](evidencias/health-aws.json)
- [Persistência RDS](evidencias/persistencia-rds.json)
- [Destroy da aplicação](evidencias/terraform-destroy.txt) e [destroy do backend](evidencias/terraform-backend-destroy.txt)

<!-- Antes da entrega: concluir as quatro respostas, remover os roteiros e avisos de rascunho, revisar links e atualizar as evidências do histórico Git. -->
