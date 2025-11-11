# 📋 Where Are the Logs?

## 🎯 Quick Answer

**Log File Location:**
```
/home/user/Genieapi/genie_app.log
```

## 🔍 How to View Logs

### **Method 1: In the Streamlit App (Easiest!)**

1. Open the app sidebar
2. Scroll to the **"📋 Logging"** section
3. You'll see the exact log file path
4. Click **"📖 View Recent Logs"** button to see the last 50 log entries

### **Method 2: Command Line**

```bash
# View entire log file
cat genie_app.log

# View last 50 lines
tail -50 genie_app.log

# Watch logs in real-time (while app is running)
tail -f genie_app.log

# Search for specific fields
grep "suggested_questions" genie_app.log
grep "Query.title" genie_app.log
grep "GENIE API RESPONSE" genie_app.log
```

### **Method 3: Text Editor**

Just open the file `genie_app.log` in any text editor.

---

## ⚠️ Important: When Do Logs Appear?

**Logs are created when:**
- ✅ App starts (you'll see "🚀 Genie Chat App Starting...")
- ✅ You ask a question and Genie responds
- ✅ format_genie_response() function is called

**Logs are NOT created when:**
- ❌ Just starting the app without asking questions
- ❌ Typing in the chat input (before pressing Enter)
- ❌ App is idle

---

## 🚀 Step-by-Step: First Time Using Logs

### **Step 1: Start the App**
```bash
streamlit run app.py
```

### **Step 2: Check Startup Logs**

Open another terminal and check:
```bash
cat genie_app.log
```

You should see:
```
2025-11-11 13:04:41 - __main__ - INFO - ================================================================================
2025-11-11 13:04:41 - __main__ - INFO - 🚀 Genie Chat App Starting...
2025-11-11 13:04:41 - __main__ - INFO - 📝 Log file: /home/user/Genieapi/genie_app.log
2025-11-11 13:04:41 - __main__ - INFO - ================================================================================
```

### **Step 3: Ask a Question**

In the Streamlit app, type and send:
```
Show me sample data
```

### **Step 4: Check Response Logs**

```bash
cat genie_app.log
```

Now you should see detailed field analysis:
```
================================================================================
GENIE API RESPONSE - Field Analysis
================================================================================
Response ID: msg_...
Status: COMPLETED
Has error: False
Number of attachments: 1
--- Attachment 1 ---
  Has text: True
  Has query: True
  Has suggested_questions: True/False  ← This is what we need!
  Query.title: EXISTS - ... / MISSING/NULL  ← This too!
...
================================================================================
```

---

## 🐛 Troubleshooting

### **"No such file or directory: genie_app.log"**

**Cause:** App hasn't been started yet, or logs aren't being created.

**Solution:**
1. Make sure you're in the `/home/user/Genieapi` directory
2. Start the app: `streamlit run app.py`
3. Ask a question in the app
4. Check again: `ls -la genie_app.log`

### **"Log file is empty or very small"**

**Cause:** You haven't asked any questions yet.

**Solution:**
- Startup logs are small (~200 bytes)
- Response logs are large (~2000+ bytes per query)
- Ask a question to generate response logs

### **"Can't see logs in terminal where I ran streamlit"**

**Cause:** Streamlit captures/redirects console output.

**Why this happens:** Streamlit manages its own output to show the web UI status.

**Solution:**
- ✅ Use the log file instead (`cat genie_app.log`)
- ✅ Or use the "View Recent Logs" button in the app sidebar
- ❌ Don't expect logs in the Streamlit terminal

---

## 📊 What the Logs Tell You

After asking a query, look for these key lines:

| Log Line | Meaning | Action |
|----------|---------|--------|
| `Has suggested_questions: True` | Field exists! | Should display in UI |
| `Has suggested_questions: False` | API doesn't return it | Org restriction or unavailable |
| `Query.title: EXISTS - ...` | Title is populated | Should display as heading |
| `Query.title: MISSING/NULL` | No title provided | Won't display (expected) |
| `Suggested questions count: 3` | 3 questions available | Should show 3 buttons |
| `Suggested questions count: 0` | Field exists but empty | Won't display (expected) |

---

## 🎯 What to Share for Diagnosis

Copy and share this section from your logs:

```bash
# Extract just the field analysis section
grep -A 30 "GENIE API RESPONSE - Field Analysis" genie_app.log
```

Or use the **"📖 View Recent Logs"** button in the app and copy the output.

---

## 🗑️ Managing Log Files

### **Clear Logs**
```bash
# Delete log file (will be recreated on next app start)
rm genie_app.log
```

### **Archive Logs**
```bash
# Save with timestamp
cp genie_app.log "genie_app_$(date +%Y%m%d_%H%M%S).log"
```

### **Prevent Logs from Growing Too Large**
```bash
# Keep only last 100 lines
tail -100 genie_app.log > genie_app.log.tmp && mv genie_app.log.tmp genie_app.log
```

---

## ✅ Checklist

- [ ] I know the log file is at: `/home/user/Genieapi/genie_app.log`
- [ ] I can view logs in the app sidebar → "📋 Logging" section
- [ ] I can view logs via: `cat genie_app.log`
- [ ] I understand logs only appear after asking questions
- [ ] I won't expect logs in the Streamlit terminal (they go to the file)

---

## 🚀 Ready!

Now run the app and check the logs:

```bash
# Terminal 1: Run app
streamlit run app.py

# Terminal 2: Watch logs
tail -f genie_app.log
```

Ask a question, then check the logs to see what fields the API returns! 🎯
