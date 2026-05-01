#!/bin/bash
# Script de déploiement simplifié pour Syndory Backend
# Usage: ./deploy-simple.sh [project-ref]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_REF="${1:-}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Syndory Backend Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Vérifier Supabase CLI
if ! command -v supabase &> /dev/null; then
    echo -e "${RED}❌ Supabase CLI non trouvé${NC}"
    exit 1
fi

# Déterminer le project ref
if [ -z "$PROJECT_REF" ]; then
    # Essayer de lire depuis le fichier de lien
    if [ -f ".supabase/temp/link-config.json" ]; then
        PROJECT_REF=$(cat .supabase/temp/link-config.json 2>/dev/null | grep -o '"project_ref":"[^"]*"' | cut -d'"' -f4)
    fi
    
    # Si toujours vide, demander
    if [ -z "$PROJECT_REF" ]; then
        echo -n "Entrez votre project ref (20 caractères): "
        read PROJECT_REF
    fi
fi

if [ -z "$PROJECT_REF" ] || [ ${#PROJECT_REF} -ne 20 ]; then
    echo -e "${RED}❌ Project ref invalide (doit faire 20 caractères)${NC}"
    echo "Exemple: abcdefghijklmnopqrst"
    exit 1
fi

echo -e "${GREEN}✅ Project ref: $PROJECT_REF${NC}"

# Lier le projet si nécessaire
echo ""
echo -e "${YELLOW}🔗 Vérification du lien...${NC}"

# Vérifier si déjà lié au bon projet
current_ref=""
if [ -f ".supabase/temp/link-config.json" ]; then
    current_ref=$(cat .supabase/temp/link-config.json 2>/dev/null | grep -o '"project_ref":"[^"]*"' | cut -d'"' -f4)
fi

if [ "$current_ref" = "$PROJECT_REF" ]; then
    echo -e "${GREEN}✅ Déjà lié au projet $PROJECT_REF${NC}"
else
    echo -e "${YELLOW}🔄 Lien au projet...${NC}"
    supabase link --project-ref "$PROJECT_REF"
fi

# Déploiement
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  📊 Migrations${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

supabase db push

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  ⚡ Edge Functions${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -n "Déployer les Edge Functions maintenant ? (y/N): "
read -r DEPLOY_FUNCTIONS

if [[ "$DEPLOY_FUNCTIONS" =~ ^[Yy]$ ]]; then
    set +e

    FUNCTIONS=(
        check-conflicts
        open-session
        mark-presence
        close-session
        send-notification
        generate-report
        validate-progression
    )

    for fn in "${FUNCTIONS[@]}"; do
        echo ""
        echo -e "${YELLOW}➡️  Déploiement: ${fn}${NC}"

        attempt=1
        max_attempts=4
        delay=5

        while [ $attempt -le $max_attempts ]; do
            supabase functions deploy "$fn"
            code=$?
            if [ $code -eq 0 ]; then
                echo -e "${GREEN}✅ ${fn} déployée${NC}"
                break
            fi

            echo -e "${YELLOW}⚠️  Échec déploiement ${fn} (tentative ${attempt}/${max_attempts}, code=${code}).${NC}"
            if [ $attempt -lt $max_attempts ]; then
                echo -e "${YELLOW}   Retry après ${delay}s...${NC}"
                sleep $delay
                delay=$((delay * 2))
            fi

            attempt=$((attempt + 1))
        done

        if [ $code -ne 0 ]; then
            echo -e "${RED}❌ ${fn} non déployée (rate limit/réseau possible). On continue...${NC}"
        fi
    done

    set -e
else
    echo -e "${YELLOW}⏭️  Déploiement Edge Functions ignoré.${NC}"
    echo -e "${YELLOW}   Tu peux le faire plus tard avec:${NC}"
    echo -e "${YELLOW}   supabase functions deploy <nom-fonction>${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ Déploiement terminé!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "URL du projet: https://app.supabase.com/project/$PROJECT_REF"
