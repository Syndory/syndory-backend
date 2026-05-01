# Documentation Edge Functions (Supabase)

Ce document décrit les **Edge Functions** du backend Syndory : objectif, logique, paramètres, réponses et exemples d’appel.

## 1) Informations générales

### 1.1 URL

Base URL (Supabase) :

- `https://<project-ref>.supabase.co/functions/v1/<function-name>`

### 1.2 Authentification

Toutes les fonctions nécessitent un utilisateur authentifié.

- Envoyer l’en-tête : `Authorization: Bearer <access_token>`
- Envoyer : `Content-Type: application/json`

### 1.3 CORS

Toutes les fonctions répondent au préflight `OPTIONS` et ajoutent des headers CORS.

### 1.4 Principes de sécurité

- Les fonctions utilisent le client Supabase avec le token de l’utilisateur (`getSupabaseClient(req)`), donc les **RLS policies** s’appliquent.
- Certaines fonctions insèrent des données via un client admin (service role). Dans ce cas, la fonction fait ses propres contrôles (rôle/permissions) avant d’écrire.

---

## 2) `mark-presence`

### Objectif
Permet à un **étudiant** de marquer sa présence à une session ouverte, avec vérification GPS.

### Endpoint
`POST /functions/v1/mark-presence`

### Body
```json
{
  "session_id": "uuid",
  "gps_lat": 6.3703,
  "gps_long": 2.3912
}
```

### Logique (résumé)
- Vérifie que l’utilisateur est authentifié.
- Valide les coordonnées GPS.
- Appelle la fonction SQL `mark_presence(p_session_id, p_student_id, p_gps_lat, p_gps_long)`.
- Retourne succès ou message d’erreur (fenêtre expirée, trop loin, session fermée…).

### Réponses
- `200` : présence marquée
- `400` : paramètres invalides / règle métier non respectée
- `401` : non authentifié
- `500` : erreur serveur

---

## 3) `open-session`

### Objectif
Permet à un **professeur** d’ouvrir une session de présence pour une séance, avec vérification GPS.

### Endpoint
`POST /functions/v1/open-session`

### Body
```json
{
  "seance_id": "uuid",
  "gps_lat": 6.3703,
  "gps_long": 2.3912,
  "marking_window_duration": 15
}
```

### Logique (résumé)
- Vérifie l’auth.
- Vérifie que la séance appartient au professeur (via `seances_view`).
- Vérifie que la séance est **le jour même**.
- Vérifie que l’ouverture est dans le **créneau horaire exact** de la séance, en timezone `Africa/Porto-Novo`.
- Vérifie que le professeur est dans le rayon de la salle (`is_within_salle_radius`).
- Vérifie qu’aucune session du professeur n’est déjà ouverte.
- Crée une ligne dans `sessions`.
- Notifie la classe via `notify_class`.

### Réponses
- `200` : session créée
- `400` : hors fenêtre / déjà une session ouverte / GPS invalide
- `403` : séance non autorisée

---

## 4) `close-session`

### Objectif
Permet à un professeur de fermer une session de présence.

### Endpoint
`POST /functions/v1/close-session`

### Body
```json
{
  "session_id": "uuid"
}
```

### Logique (résumé)
- Vérifie l’auth.
- Appelle `close_session(p_session_id, p_professor_id)`.
- La fonction SQL clôture la session et marque les absents.

---

## 5) `check-conflicts`

### Objectif
Permet de vérifier les conflits d’emploi du temps avant création/modification d’une séance.

### Accès
Réservé aux **admins**.

### Endpoint
`POST /functions/v1/check-conflicts`

### Body
```json
{
  "seance_id": "uuid (optionnel)",
  "matiere_id": "uuid",
  "professor_id": "uuid",
  "class_id": "uuid",
  "salle_id": "uuid",
  "date": "YYYY-MM-DD",
  "start_time": "HH:MM",
  "end_time": "HH:MM"
}
```

### Logique (résumé)
- Vérifie l’auth.
- Vérifie que l’utilisateur courant est admin.
- Appelle `check_schedule_conflicts(...)`.
- Retourne une liste de conflits (salle / professeur / classe).

---

## 6) `validate-progression`

### Objectif
Permet à un professeur de valider définitivement une progression.

### Endpoint
`POST /functions/v1/validate-progression`

### Body
```json
{
  "progression_id": "uuid"
}
```

### Logique (résumé)
- Vérifie l’auth.
- Charge la progression + sa séance.
- Vérifie que la séance appartient au professeur.
- Vérifie que la progression n’est pas déjà validée.
- Met à jour `progressions.is_validated = true`.

---

## 7) `send-notification`

### Objectif
Créer des notifications (table `notifications`) et cibler :
- des `user_ids` explicites, ou
- une cible logique (`all`, `filiere`, `classe`, `professors`, `students`).

### Accès
`admin`, `professor`, `class_representative`.

### Endpoint
`POST /functions/v1/send-notification`

### Body (exemple)
```json
{
  "user_ids": [],
  "target_type": "classe",
  "target_id": "uuid",
  "type": "announcement",
  "title": "Information",
  "message": "Votre message",
  "data": {"key": "value"}
}
```

### Logique (résumé)
- Vérifie l’auth.
- Vérifie le rôle.
- Construit la liste des destinataires.
- Insère les notifications via un client admin.

---

## 8) `generate-report`

### Objectif
Générer des rapports (JSON ou CSV) pour des statistiques (présence, justificatifs…).

### Accès
`admin` et `professor`.

### Endpoint
`POST /functions/v1/generate-report`

### Body
```json
{
  "report_type": "presence_global",
  "format": "json",
  "filters": {
    "class_id": "uuid",
    "start_date": "YYYY-MM-DD",
    "end_date": "YYYY-MM-DD"
  }
}
```

### Sortie
- `format=json` : JSON structuré
- `format=csv` : fichier CSV en réponse (avec `Content-Disposition`)

---

## 9) Exemples d’appel (mobile / dashboard)

### Exemple cURL
```bash
curl -X POST \
  "https://<project-ref>.supabase.co/functions/v1/mark-presence" \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"session_id":"...","gps_lat":6.37,"gps_long":2.39}'
```
