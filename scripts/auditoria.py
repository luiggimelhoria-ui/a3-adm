#!/usr/bin/env python3
"""Grava respostas da Auditoria DEC (Microsoft Forms) no Supabase.

Uso:
  python scripts/auditoria.py issue                # lê a env ISSUE_BODY (GitHub Action)
  python scripts/auditoria.py importar arquivo.xlsx  # carga do Excel exportado do Forms

Variáveis de ambiente: SUPABASE_URL, SUPABASE_SERVICE_KEY.
A nota e a aprovação NÃO são calculadas aqui: elas vêm da view
auditorias_resultado (supabase/migrations/20260930174847_auditoria_dec.sql), a única fonte da regra.
"""
import json
import os
import re
import sys
import unicodedata
import urllib.parse
import urllib.request
from datetime import datetime

# Título da coluna/pergunta no Forms -> campo no banco.
CAMPOS = {
    "id": "resposta_id",
    "hora de inicio": "inicio",
    "hora de conclusao": "conclusao",
    "email": "email",
    "nome": "nome",
    "planta": "planta",
    "area": "area",
    "equipamento": "equipamento",
    "equipamento2": "equipamento",
    "informe a tag do equipamento": "tag",
    "tag": "tag",
}
PERGUNTAS = [
    "Treinamento da operação",
    "Recursos da estação",
    "Donos do equipamento",
    "Mapa de contaminação",
    "Tratamento das fontes de contaminação",
    "Grande Limpeza e restauração",
    "Evidências Antes x Depois",
    "Abertura de etiquetas no MAXIMO",
    "Monitoramento de etiquetas abertas x fechadas",
    "Checklist de Limpeza",
    "Checklist de Inspeção",
    "Limpeza como momento de inspeção",
    "Checklist de Lubrificação",
]


def chave(texto):
    """Normaliza um título: sem acento, minúsculo, espaços simples."""
    texto = unicodedata.normalize("NFKD", str(texto)).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", texto).strip().lower()


for _i, _titulo in enumerate(PERGUNTAS, 1):
    CAMPOS[chave(_titulo)] = f"q{_i:02d}"
    CAMPOS[f"q{_i:02d}"] = f"q{_i:02d}"


def nota(valor):
    """'3 — Implementado. ...' -> 3"""
    if valor is None or valor == "":
        return None
    m = re.match(r"\s*([1-4])\b", str(valor))
    if not m:
        raise ValueError(f"Resposta sem nota de 1 a 4: {valor!r}")
    return int(m.group(1))


def data(valor):
    if valor in (None, ""):
        return None
    if isinstance(valor, datetime):
        return valor.isoformat()
    return str(valor)


def normalizar(resposta):
    """Dicionário com títulos do Forms (ou chaves do banco) -> linha da tabela."""
    linha, textos = {}, {}
    for titulo, valor in resposta.items():
        campo = CAMPOS.get(chave(titulo))
        if not campo:
            continue
        if campo.startswith("q"):
            linha[campo] = nota(valor)
            if valor not in (None, ""):
                textos[campo] = str(valor).strip()
        elif campo in ("inicio", "conclusao"):
            linha[campo] = data(valor)
        else:
            linha[campo] = None if valor is None else str(valor).strip()
    for obrigatorio in ("resposta_id", "planta", "area", "equipamento"):
        if not linha.get(obrigatorio):
            raise ValueError(f"Campo obrigatório ausente: {obrigatorio}")
    linha["respostas_texto"] = textos
    return linha


def supabase(metodo, caminho, corpo=None, prefer=None):
    url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1/" + caminho
    chave_api = os.environ["SUPABASE_SERVICE_KEY"]
    req = urllib.request.Request(url, method=metodo)
    req.add_header("apikey", chave_api)
    req.add_header("Authorization", f"Bearer {chave_api}")
    req.add_header("Content-Type", "application/json")
    if prefer:
        req.add_header("Prefer", prefer)
    dados = None if corpo is None else json.dumps(corpo).encode()
    with urllib.request.urlopen(req, dados) as r:
        texto = r.read().decode()
    return json.loads(texto) if texto else None


def gravar(linhas):
    supabase(
        "POST",
        "auditorias?on_conflict=resposta_id",
        linhas,
        prefer="resolution=merge-duplicates,return=minimal",
    )


def resumo(resposta_id):
    """Markdown com o resultado calculado pelo banco (usado no comentário da issue)."""
    [r] = supabase(
        "GET",
        "auditorias_resultado?select=planta,area,equipamento,tag,auditor,pontos,"
        "percentual,aprovado,motivo_reprovacao&resposta_id=eq."
        + urllib.parse.quote(resposta_id),
    )
    status = "✅ **APROVADA**" if r["aprovado"] else f"❌ **REPROVADA** — {r['motivo_reprovacao']}"
    return (
        f"{status}\n\n"
        f"| Planta | Área | Equipamento | Tag | Auditor | Pontos | % |\n"
        f"|---|---|---|---|---|---|---|\n"
        f"| {r['planta']} | {r['area']} | {r['equipamento']} | {r['tag'] or '—'} "
        f"| {r['auditor']} | {r['pontos']}/52 | {r['percentual']}% |\n"
    )


def de_issue(corpo):
    """O Power Automate grava o JSON da resposta no corpo da issue."""
    inicio, fim = corpo.find("{"), corpo.rfind("}")
    if inicio < 0 or fim < inicio:
        raise ValueError("Corpo da issue não contém JSON")
    return json.loads(corpo[inicio : fim + 1])


def de_xlsx(caminho):
    import openpyxl  # pip install openpyxl

    planilha = openpyxl.load_workbook(caminho, data_only=True).active
    linhas = planilha.iter_rows(values_only=True)
    cabecalho = next(linhas)
    for valores in linhas:
        if any(v not in (None, "") for v in valores):
            yield dict(zip(cabecalho, valores))


def main(argv):
    if argv[:1] == ["issue"]:
        linha = normalizar(de_issue(os.environ["ISSUE_BODY"]))
        gravar([linha])
        print(resumo(linha["resposta_id"]))
    elif argv[:1] == ["importar"] and len(argv) == 2:
        linhas = [normalizar(r) for r in de_xlsx(argv[1])]
        gravar(linhas)
        print(f"{len(linhas)} auditoria(s) importada(s).")
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
