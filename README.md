# BOB Manager v1.0 DEV

Repositório integral gerado a partir do Master Blueprint, Arquitetura Técnica,
Esquema Definitivo e Matriz de Rastreabilidade v1.0.

## Validação

```powershell
.\scripts\validate.ps1
```

## Execução

```powershell
.\scripts\run_dev.ps1
```

A aplicação arranca em modo demonstração quando `config/dev.json` não existe.

## RC1

A gestão de eventos inclui CRUD base, confirmação segura de eliminação na Agenda e na Gestão, filtragem por estado e atualização forçada dos dados ao alternar entre os separadores Agenda e Gestão. A sincronização é feita no módulo ativo `EventsModuleV2Screen`, preservando o mês selecionado na Agenda e o filtro de estado na Gestão.
