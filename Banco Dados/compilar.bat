@echo off
title AdminDelivery - Compilação de Produção
echo ============================================================
echo  Gerando build de produção do AdminDelivery...
echo ============================================================
npm run build
echo ------------------------------------------------------------
echo  ✅ Build gerada com sucesso!
echo  Os arquivos estão na pasta "dist".
pause
