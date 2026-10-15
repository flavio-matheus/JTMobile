# Contribuindo com o JTMobile

Obrigado pelo interesse! Este projeto é aberto (GPL-3.0) e aceita contribuições de operadores e desenvolvedores.

## Como começar
1. Leia o [README](README.md), [docs/ARQUITETURA.md](docs/ARQUITETURA.md) e [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md).
2. Faça um *fork*, crie uma branch (`feat/minha-ideia` ou `fix/meu-bug`) e trabalhe nela.
3. Rode antes de abrir o *pull request*:
   ```powershell
   cd app
   flutter analyze   # sem avisos
   flutter test      # todos passando
   ```
4. Abra o PR descrevendo **o que** mudou, **por quê** e **como testou** (emulador, aparelho, rádio real?).

## O que ajuda muito
* **Testes com um IC-705 real** (e relatos de divergência do protocolo) — veja [docs/ROADMAP.md](docs/ROADMAP.md) P1.
* Gravações de referência (WAV 12 kHz + saída do WSJT-X/JTDX) para regressão do decodificador.
* Port dos decodificadores de JT65/JT9 e do decodificador de maior sensibilidade do JTDX (GPL).
* Integrações de logbook (QRZ, LoTW, eQSL, Club Log).
* Traduções, acessibilidade e capturas de tela.

## Padrões
* **Idioma:** comentários/documentação em português (BR); mensagens da interface em português.
* **Comentários:** todo arquivo começa com `///` + `library;`; documente classes e métodos públicos explicando o *porquê*.
* **Testes:** lógica pura sem I/O + teste unitário. Mudanças de protocolo precisam atualizar o servidor falso em `test/icom_link_test.dart`.
* **Commits:** `tipo(escopo): resumo` (`feat`, `fix`, `docs`, `test`, `refactor`, `chore`). Commits pequenos e focados.
* **Dependências:** prefira poucas e mantidas; registre licenças de código incorporado em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
* **Sem segredos:** nunca envie credenciais, chaves de API ou *keystores*.

## Segurança e radioamadorismo
* Mudanças que afetam **TX/PTT/potência** devem ser revisadas com atenção; teste com **carga fictícia**.
* Respeite a regulamentação (licença, potência, bandas, modos). O projeto não substitui o julgamento do operador.

## Reportando problemas
Abra uma *issue* com: versão do app/commit, aparelho e Android, rádio e firmware, modo de conexão, passos para reproduzir e, se possível, logs.
Para vulnerabilidades, evite detalhes públicos e contate o mantenedor diretamente.
