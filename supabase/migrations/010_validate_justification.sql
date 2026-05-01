-- Migration 010: validation justificatif atomique

CREATE OR REPLACE FUNCTION validate_justification(
    p_justificatif_id UUID,
    p_professor_id UUID,
    p_decision justification_status,
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_justificatif justificatifs%ROWTYPE;
    v_seance seances%ROWTYPE;
BEGIN
    SELECT * INTO v_justificatif
    FROM justificatifs
    WHERE id = p_justificatif_id;

    IF v_justificatif IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Justificatif introuvable');
    END IF;

    SELECT sea.* INTO v_seance
    FROM presences p
    JOIN sessions ses ON p.session_id = ses.id
    JOIN seances sea ON ses.seance_id = sea.id
    WHERE p.id = v_justificatif.presence_id;

    IF v_seance IS NULL OR v_seance.professor_id != p_professor_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorise');
    END IF;

    IF v_justificatif.status != 'en_attente' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Justificatif deja traite');
    END IF;

    IF p_decision = 'rejeté' AND (p_rejection_reason IS NULL OR trim(p_rejection_reason) = '') THEN
        RETURN jsonb_build_object('success', false, 'error', 'rejection_reason requis');
    END IF;

    UPDATE justificatifs
    SET status = p_decision,
        reviewed_at = NOW(),
        reviewed_by = p_professor_id,
        rejection_reason = CASE WHEN p_decision = 'rejeté' THEN p_rejection_reason ELSE NULL END
    WHERE id = p_justificatif_id;

    IF p_decision = 'validé' THEN
        UPDATE presences
        SET status = 'justified'
        WHERE id = v_justificatif.presence_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'justificatif_id', p_justificatif_id,
        'status', p_decision
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
