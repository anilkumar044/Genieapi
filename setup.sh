#!/bin/bash

# Databricks Genie Chat - Quick Setup Script
# This script automates the setup process for Mac/Linux

set -e  # Exit on error

echo "=========================================="
echo "🧞 Databricks Genie Chat - Quick Setup"
echo "=========================================="
echo ""

# Check Python version
echo "1️⃣ Checking Python version..."
python3 --version || { echo "❌ Python 3 not found. Please install Python 3.8+"; exit 1; }
echo "✅ Python 3 found"
echo ""

# Create virtual environment
echo "2️⃣ Creating virtual environment..."
if [ -d "venv" ]; then
    echo "⚠️  venv directory already exists, skipping..."
else
    python3 -m venv venv
    echo "✅ Virtual environment created"
fi
echo ""

# Activate virtual environment
echo "3️⃣ Activating virtual environment..."
source venv/bin/activate
echo "✅ Virtual environment activated"
echo ""

# Install dependencies
echo "4️⃣ Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt
echo "✅ Dependencies installed"
echo ""

# Setup .env file
echo "5️⃣ Setting up environment file..."
if [ -f ".env" ]; then
    echo "⚠️  .env already exists, skipping..."
else
    cp .env.example .env
    echo "✅ .env file created from template"
fi
echo ""

echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Edit .env file with your credentials:"
echo "   nano .env"
echo ""
echo "2. Add your Databricks details:"
echo "   - DATABRICKS_HOST"
echo "   - DATABRICKS_TOKEN"
echo "   - GENIE_SPACE_ID"
echo ""
echo "3. Run the validation script:"
echo "   python test_setup.py"
echo ""
echo "4. Start the app:"
echo "   streamlit run app.py"
echo ""
echo "📚 See README.md or QUICKSTART.md for detailed instructions"
echo ""
