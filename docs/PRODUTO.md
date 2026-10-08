# Guia de produto (para o vendedor)

Modelos e checklists para transformar o pack em produto. Os itens marcados
**[preencher]** dependem de você (contas, preços, canais).

## Checklist de lançamento

- [ ] Licenças dos módulos resolvidas (ver [`../THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md)) — **bloqueador**
- [ ] Benchmark antes/depois publicado (ver `scripts/bench.sh`)
- [ ] Release `v1.1.0` criada com checksums
- [ ] Página de venda com screenshots/vídeo **[preencher]**
- [ ] Canal de suporte aberto **[preencher]**
- [ ] Política de reembolso publicada (modelo abaixo) **[preencher]**
- [ ] Licença/ativação configurada **[preencher]**

## Desinstalação limpa (cobrir todos os níveis)

Instrução única para o cliente remover **tudo**:

```sh
# 1. Reverter tudo que o pack aplicou
sh scripts/deep-tune.sh restore          # otimizações profundas (sysfs/props)
sh scripts/snapshot.sh restore latest    # settings (se salvou um snapshot)

# 2. Parar os plugins (níveis 3 e 4) no gerenciador (AxManager/Magisk/KernelSU):
#    desative/remova o módulo. O uninstall.sh de cada plugin já reverte o que aplicou.

# 3. Limpar o estado local do pack
rm -rf ~/.packotm
```

Para os níveis 1 e 2 (`.txt` e scripts), nada fica instalado — é só não executar.

## Modelo de política de reembolso **[preencher]**

> Reembolso em até **7 dias** após a compra, conforme o Código de Defesa do Consumidor
> (art. 49) para compras online. Basta solicitar por **[canal de suporte]** com o
> e-mail da compra. O reembolso é integral e não é necessário justificar.

## Canal de suporte **[preencher]**

- Discord/Telegram: **[link]**
- E-mail: **[endereço]**
- Prazo de resposta: **[ex.: 24h úteis]**

> Aviso a incluir no canal: este produto altera configurações do sistema e requer
> leitura dos avisos (especialmente o módulo térmico). Suporte não cobre aparelho
> danificado por uso fora das recomendações — ver disclaimer no README.

## Licença/ativação **[preencher]**

Opções comuns no mercado BR:
- **Hotmart / Kiwify**: entrega automática do `.zip` + área de membros para updates.
- **Gumroad**: licença por chave; bom para público internacional.
- **GitHub Releases privado**: só para quem tem acesso.

Recomendação: entregar o **zip assinado** (com `SHA256SUMS.txt`) e um link de update.
Não coloque número de série no script (quebra fácil); use a plataforma de venda para
controlar acesso.

## FAQ (rascunho — revise antes de publicar)

**Precisa de root?**
Não para tudo. Níveis 1 e 2 funcionam com Brevent/Shizuku; os módulos `angle` e
`debloat` não pedem root. `freq`, `io`, `mem`, `net`, `latency` e `thermal` pedem root.

**Vai danificar meu celular?**
O pack só altera parâmetros reversíveis e guarda o valor original antes de cada
mudança. O módulo `thermal` afrouxa a proteção de temperatura — por isso tem
confirmação explícita e uma trava que reverte automaticamente ao passar de 45 °C.

**Como eu desfaço?**
`sh scripts/deep-tune.sh restore` e `sh scripts/snapshot.sh restore latest`. Nada é
permanente.

**Funciona no meu aparelho?**
Rode `sh scripts/device-profile.sh`. A compatibilidade varia por SoC/kernel; veja
[`COMPATIBILIDADE.md`](COMPATIBILIDADE.md).

**Vocês prometem X FPS?**
Não. Rode `scripts/bench.sh` antes/depois e veja o número **do seu** aparelho. Preferimos
medir a prometer.
