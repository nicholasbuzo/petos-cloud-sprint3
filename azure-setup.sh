#!/bin/bash

# Variáveis Gerais
RESOURCE_GROUP_NAME="rg-petos"
LOCATION="chilecentral" # ou a região que seu Azure for Students permite - ex: eastus, westus, etc

# Variáveis do Web App
WEBAPP_NAME="petos-561082"
APP_SERVICE_PLAN="plan-petos"
RUNTIME="JAVA|21-java21"
APP_INSIGHTS_NAME="ai-petos"

# Variáveis do Banco de Dados (Azure Database for PostgreSQL Flexible Server)
PG_SERVER_NAME="pg-petos-561082"
PG_DB_NAME="petosdb"
PG_ADMIN_USER="dbadmin"
PG_ADMIN_PASSWORD="FIAP@2tdspo2026"

# Variáveis do GitHub
GITHUB_REPO_NAME="nicholasbuzo/petos-cloud-sprint3"
BRANCH="main"

echo "Criando resource group >>>"
az group create --name $RESOURCE_GROUP_NAME  --location "$LOCATION"

echo "Registrando provider Microsoft.DBforPostgreSQL >>>"
az provider register --namespace Microsoft.DBforPostgreSQL
echo "Aguardando registro do provider (pode levar 1-2 minutos) >>>"
while [ "$(az provider show --namespace Microsoft.DBforPostgreSQL --query registrationState -o tsv)" != "Registered" ]; do
  sleep 10
  echo "  ainda registrando..."
done

echo "Criando servidor PostgreSQL Flexible Server >>>"
az postgres flexible-server create \
  --resource-group $RESOURCE_GROUP_NAME \
  --name $PG_SERVER_NAME \
  --location "$LOCATION" \
  --admin-user $PG_ADMIN_USER \
  --admin-password $PG_ADMIN_PASSWORD \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 16 \
  --public-access 0.0.0.0-255.255.255.255 \
  --yes

echo "Criando banco de dados >>>"
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP_NAME \
  --server-name $PG_SERVER_NAME \
  --name $PG_DB_NAME

echo "Criando app-insights >>>"
az monitor app-insights component create \
  --app $APP_INSIGHTS_NAME \
  --location "$LOCATION" \
  --resource-group $RESOURCE_GROUP_NAME \
  --application-type web

echo "Criando appservice plan >>>"
az appservice plan create \
  --name $APP_SERVICE_PLAN \
  --resource-group $RESOURCE_GROUP_NAME \
  --location "$LOCATION" \
  --sku F1 \
  --is-linux

echo "Criando webapp >>>"
az webapp create \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --plan $APP_SERVICE_PLAN \
  --runtime "$RUNTIME"

echo "Habilitando autenticação básica >>>"
az resource update \
  --resource-group $RESOURCE_GROUP_NAME \
  --namespace Microsoft.Web \
  --resource-type basicPublishingCredentialsPolicies \
  --name scm \
  --parent sites/$WEBAPP_NAME \
  --set properties.allow=true

# Recuperar a Connection String do Application Insights
CONNECTION_STRING=$(az monitor app-insights component show \
  --app $APP_INSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query connectionString \
  --output tsv)

echo "Definindo configurações no web app >>>"
az webapp config appsettings set \
  --name "$WEBAPP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --settings \
    PETOS_DEV_SEED_PASSWORD="petos@dev2026" \
    PETOS_JWT_EXPIRATION_MINUTES="120" \
    PETOS_JWT_SECRET="btbTaM93//xePC28oCl6x22HG6QMbAn+QTrB5Gh9ps0=" \
    SPRING_PROFILES_ACTIVE="dev" \
    APPLICATIONINSIGHTS_CONNECTION_STRING="$CONNECTION_STRING" \
    ApplicationInsightsAgent_EXTENSION_VERSION="~3" \
    XDT_MicrosoftApplicationInsights_Mode="Recommended" \
    XDT_MicrosoftApplicationInsights_PreemptSdk="1" \
    SPRING_DATASOURCE_USERNAME="$PG_ADMIN_USER" \
    SPRING_DATASOURCE_PASSWORD="$PG_ADMIN_PASSWORD" \
    SPRING_DATASOURCE_URL="jdbc:postgresql://$PG_SERVER_NAME.postgres.database.azure.com:5432/$PG_DB_NAME?sslmode=require"

echo "Reiniciando Web App e conectando App Insights"
az webapp restart --name $WEBAPP_NAME --resource-group $RESOURCE_GROUP_NAME

az monitor app-insights component connect-webapp \
  --app $APP_INSIGHTS_NAME \
  --web-app $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP_NAME

echo "Configurando CI/CD"
EXISTING_SOURCE=$(az webapp deployment source show \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query repoUrl -o tsv 2>/dev/null)

if [ -z "$EXISTING_SOURCE" ]; then
  echo "Nenhuma integração de CI/CD encontrada, configurando pela primeira vez >>>"
  az webapp deployment github-actions add \
    --name $WEBAPP_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --repo $GITHUB_REPO_NAME \
    --branch $BRANCH \
    --login-with-github
else
  echo "CI/CD já configurado ($EXISTING_SOURCE) — pulando, para não sobrescrever o .yaml já corrigido no repositório."
fi