# ⚡ Quick Start Guide - Get Running in 5 Minutes

## For Your 2-Day Demo

### 1️⃣ Get Your Credentials (5 mins)

**What you need:**
1. Databricks workspace URL
2. Personal access token
3. Genie Space ID

**Where to find them:**

📍 **Workspace URL**: Look at your browser when logged into Databricks
   - Example: `https://dbc-abc12345-6789.cloud.databricks.com`

🔑 **Access Token**:
   1. In Databricks: Click your profile → User Settings
   2. Go to Developer → Access tokens
   3. Click "Generate new token"
   4. Copy it immediately!

🧞 **Genie Space ID**:
   1. Open your Genie Space in Databricks
   2. Look at the URL: `.../genie/rooms/01abc123...`
   3. Copy the long ID after `/rooms/`

---

### 2️⃣ Setup (3 mins)

```bash
# Navigate to project
cd Genieapi

# Create virtual environment
python -m venv venv

# Activate it
source venv/bin/activate  # Mac/Linux
# OR
venv\Scripts\activate     # Windows

# Install dependencies
pip install -r requirements.txt

# Setup environment
cp .env.example .env
```

---

### 3️⃣ Configure (2 mins)

Edit the `.env` file (use any text editor):

```bash
nano .env
```

Fill in your values:
```env
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=dapi123abc456def789...
GENIE_SPACE_ID=01abc123def456...
```

**Save and close** (Ctrl+X, then Y, then Enter in nano)

---

### 4️⃣ Run! (1 min)

```bash
streamlit run app.py
```

Your browser should open automatically to `http://localhost:8501`

If not, open your browser and go to that URL manually.

---

## ✅ Demo Checklist

Before your demo:
- [ ] App opens without errors
- [ ] You can send a test query
- [ ] Response appears (may take 30-60 seconds)
- [ ] You can ask a follow-up question
- [ ] "New Conversation" button works
- [ ] Example queries work

---

## 💡 Demo Tips

### Start with Simple Queries
1. "Show me sample data from my tables"
2. "What tables are available?"
3. "Count rows in [your table name]"

### Impress Your Audience
1. "Show me top 10 [entities] by [metric]"
2. "What's the trend of [metric] over time?"
3. "Compare [metric] across [dimension]"

### Show the Features
1. ✨ Natural language - no SQL needed
2. 🔄 Conversation context - follow-up questions work
3. 📊 SQL transparency - see generated queries
4. 💡 Example queries - built-in suggestions

---

## 🆘 Emergency Troubleshooting

### App won't start?
```bash
# Check Python version (need 3.8+)
python --version

# Reinstall dependencies
pip install --upgrade -r requirements.txt

# Check .env file exists
ls -la .env
```

### "Configuration Missing" error?
```bash
# Verify .env exists and has content
cat .env

# Make sure no extra spaces or quotes
# Should look exactly like:
# DATABRICKS_HOST=https://...
# Not: DATABRICKS_HOST = "https://..."
```

### Connection fails?
- Check workspace URL has `https://`
- Verify token hasn't expired
- Test token: Try logging into Databricks UI
- Check network: Can you access Databricks in browser?

### Queries timeout?
- This is normal for complex queries
- Try a simpler query first
- Genie can take 30-60 seconds (or more)

---

## 🎬 Demo Script (2 minutes)

**Opening:**
> "Let me show you how we can query data using natural language, powered by Databricks Genie API."

**Demo Flow:**
1. Show the clean interface
2. Type: "Show me my top customers" (or relevant query)
3. While waiting: "Genie is analyzing the query and generating SQL"
4. When response appears: "Here's the answer, and here's the SQL it generated"
5. Ask follow-up: "What about last month?"
6. Show: "Notice it maintains context from our conversation"
7. Click example query: "We have pre-built examples too"
8. Show sidebar: "Easy to start new conversations or clear history"

**Closing:**
> "This is all happening through the Genie API - the same AI that powers Databricks BI, now accessible from any custom application."

---

## 📸 Screenshot Checklist

For your presentation, capture:
1. Clean interface with chat ready
2. Query being typed
3. Response with both text and SQL
4. Follow-up question showing context
5. Example queries sidebar

---

## 🔥 Last-Minute Tips

- **Test beforehand**: Run through your demo at least once
- **Have backup queries**: Prepare 3-4 queries that work
- **Know your data**: Use table/column names that exist
- **Plan for delays**: Genie can take 30-60 seconds
- **Have a story**: Tie queries to a business use case

---

## 📞 Need Help?

**5 Minutes Before Demo:**
- Check internet connection
- Close other apps (free up memory)
- Have browser ready at localhost:8501
- Keep Databricks workspace open in another tab

**During Demo:**
- If one query fails, try another
- Use example queries as backup
- The "thinking" spinner is normal - don't panic!

---

**Good luck with your demo! 🚀**
