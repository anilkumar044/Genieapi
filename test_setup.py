"""
Quick setup validation script
Run this to check if your environment is configured correctly
"""

import sys
import os
from pathlib import Path

def check_python_version():
    """Check if Python version is 3.8+"""
    version = sys.version_info
    if version.major >= 3 and version.minor >= 8:
        print(f"✅ Python version: {version.major}.{version.minor}.{version.micro}")
        return True
    else:
        print(f"❌ Python version {version.major}.{version.minor} is too old. Need 3.8+")
        return False

def check_dependencies():
    """Check if required packages are installed"""
    required = ['streamlit', 'databricks', 'dotenv']
    all_installed = True

    for package in required:
        try:
            if package == 'dotenv':
                __import__('dotenv')
                module_name = 'python-dotenv'
            else:
                __import__(package)
                module_name = package
            print(f"✅ {module_name} installed")
        except ImportError:
            print(f"❌ {module_name} not installed")
            all_installed = False

    return all_installed

def check_env_file():
    """Check if .env file exists and has required variables"""
    env_file = Path('.env')

    if not env_file.exists():
        print("❌ .env file not found")
        print("   Run: cp .env.example .env")
        return False

    print("✅ .env file exists")

    # Check for required variables
    required_vars = ['DATABRICKS_HOST', 'DATABRICKS_TOKEN', 'GENIE_SPACE_ID']
    from dotenv import load_dotenv
    load_dotenv()

    all_set = True
    for var in required_vars:
        value = os.getenv(var)
        if value and value != f"your-{var.lower().replace('_', '-')}":
            print(f"✅ {var} is set")
        else:
            print(f"❌ {var} is not set or still has placeholder value")
            all_set = False

    return all_set

def check_files():
    """Check if all required files exist"""
    required_files = ['app.py', 'requirements.txt', '.env.example']
    all_exist = True

    for file in required_files:
        if Path(file).exists():
            print(f"✅ {file} exists")
        else:
            print(f"❌ {file} missing")
            all_exist = False

    return all_exist

def main():
    """Run all checks"""
    print("=" * 50)
    print("🔍 Genie Chat App - Setup Validation")
    print("=" * 50)
    print()

    print("1️⃣ Checking Python version...")
    python_ok = check_python_version()
    print()

    print("2️⃣ Checking required files...")
    files_ok = check_files()
    print()

    print("3️⃣ Checking dependencies...")
    deps_ok = check_dependencies()
    print()

    print("4️⃣ Checking environment configuration...")
    env_ok = check_env_file()
    print()

    print("=" * 50)
    if all([python_ok, files_ok, deps_ok, env_ok]):
        print("🎉 All checks passed! You're ready to run:")
        print("   streamlit run app.py")
    else:
        print("⚠️  Some checks failed. Please fix the issues above.")
        print()
        print("Quick fixes:")
        if not deps_ok:
            print("  • Install dependencies: pip install -r requirements.txt")
        if not env_ok:
            print("  • Configure .env: cp .env.example .env")
            print("  • Edit .env with your Databricks credentials")
    print("=" * 50)

if __name__ == "__main__":
    main()
