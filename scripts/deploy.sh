#!/bin/bash
# Script de déploiement Syndory Backend sur Supabase
# Usage: ./deploy.sh [environment]
# Exemple: ./deploy.sh production

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV=${1:-production}
PROJECT_REF=""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Syndory Backend Deployment Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Vérification des prérequis
echo -e "${YELLOW}🔍 Vérification des prérequis...${NC}"

if ! command -v supabase &> /dev/null; then
    echo -e "${RED}❌ Supabase CLI non trouvé${NC}"
    echo "Installez-le avec: npm install -g supabase"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq non trouvé (optionnel, pour le formatage JSON)${NC}"
fi

echo -e "${GREEN}✅ Supabase CLI trouvé${NC}"

# Détection du project ref
echo ""
echo -e "${YELLOW}🔧 Configuration du projet...${NC}"

if [ -f "supabase/config.toml" ]; then
    PROJECT_REF=$(grep -E '^project_id' supabase/config.toml | cut -d'=' -f2 | tr -d ' "')
fi

if [ -z "$PROJECT_REF" ]; then
    echo -e "${YELLOW}⚠️  Project ref non trouvé dans config.toml${NC}"
    echo -n "Entrez votre project ref (trouvé dans l'URL Supabase): "
    read PROJECT_REF
fi

if [ -z "$PROJECT_REF" ]; then
    echo -e "${RED}❌ Project ref requis${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Project ref: ${PROJECT_REF}${NC}"

# Connexion au projet
echo ""
echo -e "${YELLOW}🔗 Connexion au projet Supabase...${NC}"

if ! supabase status &> /dev/null; then
    echo "Projet non lié. Lien en cours..."
    supabase link --project-ref "$PROJECT_REF"
fi

echo -e "${GREEN}✅ Projet lié${NC}"

# Déploiement des migrations
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  📊 ÉTAPE 1: Migrations Base de données${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${YELLOW}📦 Application des migrations...${NC}"
echo "Migrations à appliquer:"
echo "  - 001_initial_schema.sql (Tables, enums, indexes)"
echo "  - 002_rls_policies.sql (RLS policies + helpers)"
echo "  - 003_functions_triggers.sql (Fonctions métier)"
echo "  - 004_constraints_and_cron.sql (Contraintes + cron)"
echo "  - 005_automatic_notifications.sql (Notifications auto)"
echo "  - 006_storage_policies.sql (Storage RLS)"
echo ""

read -p "Continuer avec le déploiement des migrations? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    supabase db push
    echo -e "${GREEN}✅ Migrations appliquées${NC}"
else
    echo -e "${YELLOW}⚠️  Migrations ignorées${NC}"
fi

# Déploiement des Edge Functions
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  ⚡ ÉTAPE 2: Edge Functions${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${YELLOW}🚀 Déploiement des fonctions...${NC}"
echo "Fonctions à déployer:"
echo "  - open-session (Ouverture session présence)"
echo "  - mark-presence (Marquage présence étudiant)"
echo "  - close-session (Fermeture session prof)"
echo "  - generate-report (Génération rapports)"
echo "  - send-notification (Envoi notifications)"
echo "  - test-notification (Test notifications)"
echo ""

read -p "Déployer toutes les Edge Functions? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    supabase functions deploy
    echo -e "${GREEN}✅ Edge Functions déployées${NC}"
else
    echo -e "${YELLOW}⚠️  Edge Functions ignorées${NC}"
fi

# Configuration des secrets
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  🔐 ÉTAPE 3: Secrets / Variables d'environnement${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${YELLOW}⚠️  Les secrets suivants doivent être configurés:${NC}"
echo "  - SUPABASE_URL"
echo "  - SUPABASE_SERVICE_ROLE_KEY"
echo ""
echo "Commande pour les configurer:"
echo "  supabase secrets set SUPABASE_URL=https://${PROJECT_REF}.supabase.co"
echo "  supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<votre_clé>"
echo ""
echo -e "${YELLOW}Voulez-vous configurer les secrets maintenant? (y/n)${NC} "
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -n "SUPABASE_URL [https://${PROJECT_REF}.supabase.co]: "
    read SUPABASE_URL
    SUPABASE_URL=${SUPABASE_URL:-https://${PROJECT_REF}.supabase.co}
    
    echo -n "SUPABASE_SERVICE_ROLE_KEY: "
    read -s SUPABASE_SERVICE_ROLE_KEY
    echo
    
    if [ -n "$SUPABASE_SERVICE_ROLE_KEY" ]; then
        supabase secrets set SUPABASE_URL="$SUPABASE_URL"
        supabase secrets set SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY"
        echo -e "${GREEN}✅ Secrets configurés${NC}"
    else
        echo -e "${YELLOW}⚠️  Clé vide, secrets non configurés${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Secrets non configurés (à faire manuellement)${NC}"
fi

# Vérification finale
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  ✅ ÉTAPE 4: Vérification${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${YELLOW}🔍 Vérification du déploiement...${NC}"

echo ""
echo "Tables créées:"
supabase migration list 2>/dev/null || echo "  (Liste non disponible en local)"

echo ""
echo "Edge Functions:"
supabase functions list 2>/dev/null || echo "  (Liste disponible dans le dashboard)"

# Récapitulatif
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 Déploiement terminé!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Projet: ${PROJECT_REF}"
echo "URL: https://app.supabase.com/project/${PROJECT_REF}"
echo ""
echo "Prochaines étapes:"
echo "  1. Vérifier les tables dans le Dashboard Supabase"
echo "  2. Tester les Edge Functions dans le Dashboard"
echo "  3. Configurer les buckets storage si nécessaire"
echo "  4. Importer les données de test (seed)"
echo ""
echo "Commandes utiles:"
echo "  supabase db reset          # Réinitialiser la base (local)"
echo "  supabase functions serve     # Tester les fonctions localement"
echo "  supabase status            # Vérifier l'état"
echo ""
