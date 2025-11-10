@echo off
REM Databricks Genie Chat - Quick Setup Script for Windows

echo ==========================================
echo 🧞 Databricks Genie Chat - Quick Setup
echo ==========================================
echo.

REM Check Python version
echo 1️⃣ Checking Python version...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Python not found. Please install Python 3.8+
    exit /b 1
)
python --version
echo ✅ Python found
echo.

REM Create virtual environment
echo 2️⃣ Creating virtual environment...
if exist venv (
    echo ⚠️  venv directory already exists, skipping...
) else (
    python -m venv venv
    echo ✅ Virtual environment created
)
echo.

REM Activate virtual environment
echo 3️⃣ Activating virtual environment...
call venv\Scripts\activate.bat
echo ✅ Virtual environment activated
echo.

REM Install dependencies
echo 4️⃣ Installing dependencies...
python -m pip install --upgrade pip
pip install -r requirements.txt
echo ✅ Dependencies installed
echo.

REM Setup .env file
echo 5️⃣ Setting up environment file...
if exist .env (
    echo ⚠️  .env already exists, skipping...
) else (
    copy .env.example .env
    echo ✅ .env file created from template
)
echo.

echo ==========================================
echo ✅ Setup complete!
echo ==========================================
echo.
echo 📝 Next steps:
echo.
echo 1. Edit .env file with your credentials:
echo    notepad .env
echo.
echo 2. Add your Databricks details:
echo    - DATABRICKS_HOST
echo    - DATABRICKS_TOKEN
echo    - GENIE_SPACE_ID
echo.
echo 3. Run the validation script:
echo    python test_setup.py
echo.
echo 4. Start the app:
echo    streamlit run app.py
echo.
echo 📚 See README.md or QUICKSTART.md for detailed instructions
echo.
pause
