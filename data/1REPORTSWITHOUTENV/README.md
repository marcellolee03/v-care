# Relatórios de Vulnerabilidades (`data/REPORTSWITHOUTENV`)

Este diretório contém os relatórios consolidados de vulnerabilidades extraídas de fontes diversas e estruturadas no padrão oficial do OpenVAS/GVM (26 colunas), organizados em 3 lotes complementares para o benchmark de automação de patches com LLMs no pipeline do `v-care`.

---

## 1. Estrutura de Pastas de Vulnerabilidades (`data/REPORTSWITHOUTENV/data/`)

Ao todo, foram gerados **111 cenários de vulnerabilidades estritamente inéditos** (nenhum deles se repete entre si e nenhum deles existe nas 53 pastas da raiz do repositório), divididos em **3 lotes metodológicos**:

```text
data/1REPORTSWITHOUTENV/data/
├── <47 pastas com NVT OID e CVE>/     <- Lote Principal: OID padrão + CVE + Solução prévia
│   ├── patches/
│   └── report.csv
│
├── 1DATAWITHOUTOID/                    <- Lote 2 (43 pastas): CVEs no Apache sem OID padrão
│   ├── cve-2014-0098/
│   ├── cve-2021-26690/
│   └── ... (43 pastas)
│
└── 2DATAWITHOUTCVE/                    <- Lote 3 (21 pastas): CVSS > 0 com OID padrão sem CVE
    ├── distributed-ruby-druby-drb-multiple-rce-vulnerabil/
    ├── java-rmi-server-insecure-default-configuration-rem/
    ├── possible-backdoor-ingreslock/
    ├── postgresql-default-credentials-postgresql-protocol/
    └── ... (21 pastas)
```

---

### Detalhamento dos 3 Lotes de Avaliação

#### Lote 1: Lote Principal (47 Pastas na raiz de `data/`)
- **Foco**: Vulnerabilidades tradicionais com `NVT OID` oficial e `CVE` registrado.
- **Características**: 100% de preenchimento nos campos técnicos (`Solution`, `Vulnerability Insight`, `Impact`, `Detection Method`).
- **Nomenclatura**: Nome da falha em `kebab-case` derivado de `NVT Name` (ex.: `distcc-rce-vulnerability-cve-2004-2687`, `vsftpd-compromised-source-packages-backdoor-vulner`).

#### Lote 2: Sem OID Padrão (`1DATAWITHOUTOID/` - 43 Pastas)
- **Foco**: Vulnerabilidades inéditas em Apache HTTP Server identificadas via correlação CPE/CVE pelo OpenVAS.
- **Características**: A coluna `CVEs` está preenchida; `Summary` e `Specific Result` descrevem a falha detalhadamente; as colunas `Solution` e `Insight` estão vazias.
- **Papel no Benchmark**: Caso de teste ideal para **dedução autônoma de patches pela LLM** a partir da descrição técnica e do CVE.
- **Nomenclatura**: Nome padronizado pelo código do CVE em minúsculas (ex.: `cve-2021-26690`).

#### Lote 3: Sem CVE Registrado (`2DATAWITHOUTCVE/` - 21 Pastas)
- **Foco**: Falhas reais com **CVSS > 0.0** (até 10.0), com `NVT OID` oficial e `Solution` 100% preenchida, mas sem código CVE atribuído.
- **Características**: Inclui backdoors críticos (Ingreslock, UnrealIRCd), RCEs de serviços mal configurados (Java RMI, dRuby), logins sem senha/senhas padrão (PostgreSQL, rlogin, VNC, SSH) e enfraquecimento criptográfico de rede (cifras e algoritmos MAC/KEX fracos no SSH).
- **Papel no Benchmark**: Caso de teste para **hardening de serviços, remoção de backdoors e sanitização de credenciais/criptografia**.
- **Nomenclatura**: Nome da falha em `kebab-case` derivado de `NVT Name` (ex.: `possible-backdoor-ingreslock`).
