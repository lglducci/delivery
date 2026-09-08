 
DROP TABLE IF EXISTS contab.conciliacao_tmp;

CREATE TABLE contab.conciliacao_tmp (
    id               BIGSERIAL PRIMARY KEY,

    empresa_id       BIGINT NOT NULL,
    conta_id         BIGINT,

    -- E = Extrato / R = Razão
    origem           CHAR(1) NOT NULL,

    -- id do lançamento do razão ou sequência do extrato
    origem_id        BIGINT,

    -- somente para registros do razão
    lote_id          BIGINT,

    data_mov         DATE NOT NULL,

    -- C = Crédito / D = Débito
    tipo             CHAR(1) NOT NULL,

    valor            NUMERIC(15,2) NOT NULL,
 

    historico        TEXT,

    -- controle da conciliação
    achei            BOOLEAN DEFAULT FALSE,

    -- id da linha correspondente na própria conciliacao_tmp
    par_id           BIGINT,

    -- EXATO
    -- DIA_CONCILIADO
    -- DATA_DIFERENTE
    -- VALOR_DIFERENTE
    -- NAO_ENCONTRADO
    motivo           TEXT,

    -- ALTERAR_DATA
    -- ALTERAR_VALOR
    -- EXCLUIR_LOTE
    -- INCLUIR_LANCAMENTO
    acao             TEXT,

    -- sugestões
    data_sugerida    DATE,
    valor_sugerido   NUMERIC(15,2)
);

CREATE INDEX idx_conc_tmp_origem
ON contab.conciliacao_tmp(origem);

CREATE INDEX idx_conc_tmp_achei
ON contab.conciliacao_tmp(achei);

CREATE INDEX idx_conc_tmp_data
ON contab.conciliacao_tmp(data_mov);

CREATE INDEX idx_conc_tmp_valor
ON contab.conciliacao_tmp(valor);

 
CREATE INDEX idx_conc_tmp_origem_achei
ON contab.conciliacao_tmp(origem, achei);
 