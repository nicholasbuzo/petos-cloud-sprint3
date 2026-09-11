#!/bin/bash

# Variáveis Gerais
RESOURCE_GROUP_NAME="rg-petos"
LOCATION="chilecentral" # ou a região que seu Azure for Students permite - ex: eastus, westus, etc

# Variáveis do Web App
WEBAPP_NAME="petos-561082"
APP_SERVICE_PLAN="plan-petos"
RUNTIME="JAVA|21-java21"
APP_INSIGHTS_NAME="ai-petos"

# Variáveis do Banco de Dados (Azure SQL)
SQL_SERVER_NAME="sqlserver-petos-561082"
SQL_DB_NAME="petosdb"
SQL_ADMIN_USER="dbadmin"
SQL_ADMIN_PASSWORD="FIAP@2tdspo2026"

# Variáveis do GitHub
GITHUB_REPO_NAME="nicholasbuzo/petos-cloud-sprint3"
BRANCH="main"

echo "Criando resource group >>>"
az group create --name $RESOURCE_GROUP_NAME  --location "$LOCATION"

echo "Criando server >>>"
az sql server create \
  --name $SQL_SERVER_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --location "$LOCATION" \
  --admin-user $SQL_ADMIN_USER \
  --admin-password $SQL_ADMIN_PASSWORD

echo "Criando banco de dados >>>"
az sql db create \
  --resource-group $RESOURCE_GROUP_NAME \
  --server $SQL_SERVER_NAME \
  --name $SQL_DB_NAME \
  --service-objective Basic

echo "Criando regra de firewall >>>"
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP_NAME \
  --server $SQL_SERVER_NAME \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 255.255.255.255

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
    SPRING_DATASOURCE_USERNAME="$SQL_ADMIN_USER" \
    SPRING_DATASOURCE_PASSWORD="$SQL_ADMIN_PASSWORD" \
    SPRING_DATASOURCE_URL="jdbc:sqlserver://$SQL_SERVER_NAME.database.windows.net:1433;database=$SQL_DB_NAME;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"

echo "Reiniciando Web App e conectando App Insights"
az webapp restart --name $WEBAPP_NAME --resource-group $RESOURCE_GROUP_NAME

az monitor app-insights component connect-webapp \
  --app $APP_INSIGHTS_NAME \
  --web-app $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP_NAME

echo "Configurando CI/CD"
az webapp deployment github-actions add \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --repo $GITHUB_REPO_NAME \
  --branch $BRANCH \
  --login-with-github
  