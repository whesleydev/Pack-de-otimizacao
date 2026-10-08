# Roadmap — do pack técnico ao produto

O pack já tem base técnica sólida (4 níveis, snapshot, reversão por módulo, auditoria).
O que falta para virar **produto comprável** é empacotamento, garantias e suporte.

Este documento separa o que é **engenharia** (dá para fazer aqui) do que **depende do
dono do projeto** (contas, permissões, canais). A ordem segue impacto real.

## Prioridade

### 1. Direito de redistribuição dos módulos (bloqueador legal)
- [x] `THIRD-PARTY-NOTICES.md` com status de licença de cada módulo.
- [x] `scripts/check-licenses.sh` e build estrito (`STRICT_LICENSES=1`).
- [ ] **Dono:** obter permissão escrita, confirmar licença, remover ou substituir cada
      módulo sem licença (14 de 16). Sem isso, **não vender**.
- [ ] Guardar as autorizações em `modules/permissions.tsv` (autor, data, prova).

### 2. Prova de resultado (benchmark) — é o que justifica o preço
- [x] `scripts/bench.sh` (RAM, temperatura, CPU, refresh, abertura de app) + relatório.
- [ ] **Dono:** rodar antes/depois em 2–3 aparelhos reais e publicar os números
      (com o modelo e o método). Número honesto > promessa.

### 3. Build/release automático
- [x] CI em push/PR: sintaxe, shellcheck (`-S error`), testes, segredos, licenças.
- [x] Release por tag com `SHA256SUMS.txt` e corpo = `CHANGELOG.md`.
- [ ] **Dono:** criar a tag `v1.1.0` e conferir a release publicada.

### 4. Testes automatizados
- [x] `tests/run.sh` com stubs (`settings`/`cmd`/`am`/`getprop`), cobrindo
      apply→restore, reversão por módulo e o marcador `deep_mark`.

### 5. Versionamento e changelog
- [x] `CHANGELOG.md` + `VERSION` + tag `v1.1.0`.
- [ ] **Dono:** decidir o canal de update (o plugin AxManager pode checar sozinho).

### 6. Segurança reforçada (térmico)
- [x] Confirmação explícita (`THERMAL_OK=1` ou "s") e **trava automática** que reverte
      o módulo `thermal` ao passar de `THERMAL_MAX_C` (padrão 45 °C) ou ao carregar
      (`THERMAL_STOP_CHARGING=1`).
- [x] Aviso na UI e no README.

### 7. Compatibilidade por aparelho
- [x] `scripts/device-profile.sh` (detecta SoC/GPU/kernel e recomenda módulos).
- [x] `docs/COMPATIBILIDADE.md` com tabela de famílias e espaço para modelos testados.
- [ ] **Dono:** testar em aparelhos reais e preencher a tabela.

### 8. Incidente de segurança
- [x] `apps_otm.zip` removido do versionamento; `docs/SEGURANCA.md` com o passo a passo.
- [x] `scripts/check-secrets.sh` rodando no CI.
- [ ] **Dono:** revogar o token exposto e purgar o histórico (`git filter-repo`/BFG).

### 9. UX de produto
- [ ] **Dono/engenharia:** instalador único (um `.zip` ou one-liner Termux) em vez de
      clonar o git; WebUI com presets (equilibrado/game/extremo) e status ao vivo.
- [ ] Idiomas EN/ES (hoje tudo em PT-BR).

### 10. Infra de venda
- [ ] **Dono:** licença/ativação (Hotmart/Kiwify/Gumroad), canal de suporte
      (Discord/Telegram), FAQ e política de reembolso. Ver `docs/PRODUTO.md`.

## O que NÃO vamos fazer

- Prometer FPS que não medimos.
- Empacotar módulo de terceiro sem licença.
- Esconder risco (térmico, placebo). A auditoria existe para manter o pack honesto.
