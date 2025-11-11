# 🔍 Logging Instructions - Diagnosing API Field Availability

## 📋 Overview

Your app now has comprehensive logging to capture **exactly** what fields the Databricks Genie API returns. This will help us determine if:
- ✅ Organization is restricting certain API fields
- ✅ Fields exist but are null/empty
- ✅ Fields exist with data but aren't displaying (code bug)

---

## 🎯 What You're Investigating

You implemented 6 features but only see 3:

### ✅ **Working (Visible in UI):**
1. Query Description
2. Generated SQL
3. Response Time

### ❓ **Missing (Not visible in UI):**
4. Query Title
5. Pagination Info (e.g., "Showing 100 of 50,000 rows")
6. Suggested Follow-up Questions

---

## 🚀 How to Run with Logging

### **Step 1: Start the App**
```bash
streamlit run app.py
```

**Important:** Keep your terminal/console visible so you can see the log output in real-time!

### **Step 2: Ask a Query**

Use your standard test query:
```
Calculate SQL Warehouse usage costs for warehouse_id in ('abc123', 'def456')
between 2025-10-01 and 2025-11-10
```

Or any query that returns data.

### **Step 3: Watch the Terminal Output**

As soon as Genie responds, you'll see detailed logging output like this:

```
2025-11-11 10:30:45 - __main__ - INFO - ================================================================================
2025-11-11 10:30:45 - __main__ - INFO - GENIE API RESPONSE - Field Analysis
2025-11-11 10:30:45 - __main__ - INFO - ================================================================================
2025-11-11 10:30:45 - __main__ - INFO - Response ID: msg_abc123...
2025-11-11 10:30:45 - __main__ - INFO - Status: COMPLETED
2025-11-11 10:30:45 - __main__ - INFO - Has error: False
2025-11-11 10:30:45 - __main__ - INFO - Timestamps - created: 1731321045000, updated: 1731321065000
2025-11-11 10:30:45 - __main__ - INFO - Number of attachments: 1
2025-11-11 10:30:45 - __main__ - INFO - --- Attachment 1 ---
2025-11-11 10:30:45 - __main__ - INFO -   Has text: True
2025-11-11 10:30:45 - __main__ - INFO -   Has query: True
2025-11-11 10:30:45 - __main__ - INFO -   Has suggested_questions: True  ← KEY!
2025-11-11 10:30:45 - __main__ - INFO -   Has query_result_metadata: True
2025-11-11 10:30:45 - __main__ - INFO -   Query.title: EXISTS - Top 10 SQL Warehouses  ← KEY!
2025-11-11 10:30:45 - __main__ - INFO -   Query.description: EXISTS - Calculates total DBU usage...
2025-11-11 10:30:45 - __main__ - INFO -   Query.statement_id: EXISTS
2025-11-11 10:30:45 - __main__ - INFO -   Suggested questions type: GenieSuggestedQuestionsAttachment  ← KEY!
2025-11-11 10:30:45 - __main__ - INFO -   Suggested questions count: 3  ← KEY!
2025-11-11 10:30:45 - __main__ - INFO - ================================================================================
```

---

## 🔍 What to Look For

### **🎯 Key Lines to Check:**

#### **1. Suggested Questions**
```
Has suggested_questions: True/False
Suggested questions type: GenieSuggestedQuestionsAttachment
Suggested questions count: 3
```

**What this tells you:**
- `False` → Field not returned by API (org restriction or Genie didn't provide)
- `True` + count: 0 → Field exists but empty
- `True` + count: 3 → Field has data! (should display in UI)

#### **2. Query Title**
```
Query.title: EXISTS - Top 10 SQL Warehouses
```
OR
```
Query.title: MISSING/NULL
```

**What this tells you:**
- `EXISTS` → Field has data (should display in UI)
- `MISSING/NULL` → Field not provided by API

#### **3. Query Result Metadata**
```
Has query_result_metadata: True/False
```

**What this tells you:**
- `True` → Pagination info should be available
- `False` → No pagination info from API

---

## 📊 Log File Location

Logs are also written to a file for easier review:

**File:** `genie_app.log` (in the same directory as app.py)

```bash
# View the log file
cat genie_app.log

# Or tail for recent entries
tail -50 genie_app.log

# Or search for specific field
grep "suggested_questions" genie_app.log
grep "Query.title" genie_app.log
```

---

## 🧪 Test Scenarios

### **Scenario A: Fields Exist with Data**

**Log output:**
```
Has suggested_questions: True
Suggested questions count: 3
Query.title: EXISTS - Revenue Analysis
```

**Conclusion:** API returns the fields! There's a **display bug** in the code.

**Next step:** We'll debug why the display functions aren't working.

---

### **Scenario B: Fields Missing/Null**

**Log output:**
```
Has suggested_questions: False
Suggested questions count: 0
Query.title: MISSING/NULL
```

**Conclusion:** API is NOT returning these fields. Possible causes:
- Organization policy restricts certain fields
- Genie Space configuration
- API version differences
- Query type doesn't trigger these fields

**Next step:** We'll investigate org settings or adapt the app to work without these fields.

---

### **Scenario C: Fields Inconsistent**

**Log output (Query 1):**
```
Has suggested_questions: True
Query.title: EXISTS - Sales Report
```

**Log output (Query 2):**
```
Has suggested_questions: False
Query.title: MISSING/NULL
```

**Conclusion:** Fields are **query-dependent**. Some queries get them, others don't.

**Next step:** We'll add better null checking and graceful degradation.

---

## 📝 What to Share

After running your test query, please share:

### **1. Terminal Output**

Copy the section between the `====` lines:
```
================================================================================
GENIE API RESPONSE - Field Analysis
================================================================================
[All the logging lines here]
================================================================================
```

### **2. What You Saw in the UI**

Tell me which features appeared:
- ✅ Natural language answer
- ✅ Query Description
- ✅ Generated SQL
- ✅ Response Time
- ❓ Query Title (big heading before description)
- ❓ Pagination info (blue box showing row counts)
- ❓ Suggested questions (buttons below the table)

### **3. Your Test Query**

What question did you ask Genie?

---

## 🐛 Debug Mode (Optional)

For **even more** detail, enable Debug Mode:

1. Open sidebar
2. Scroll to "Advanced" section
3. Check "Debug Mode"
4. Ask your query again

This will show **all response fields** directly in the UI, not just the logs.

---

## 📋 Quick Checklist

- [ ] Started app: `streamlit run app.py`
- [ ] Terminal visible (showing real-time logs)
- [ ] Asked test query
- [ ] Saw logging output in terminal
- [ ] Noted which features appeared in UI
- [ ] Copied logging output from terminal
- [ ] Checked `genie_app.log` file exists

---

## 🎯 Expected Outcome

After you run this, we'll know:

1. **Which fields your org's API returns**
2. **Which fields are always null**
3. **If there's a display bug or API limitation**

Then we can:
- Fix display bugs if fields exist
- Document which features work in your environment
- Add graceful fallbacks for missing fields

---

## 💡 Tips

**Tip 1: Run Multiple Queries**
Different query types might return different fields:
- Simple: "Show me sample data"
- Aggregation: "Top 10 customers by revenue"
- Time-based: "Sales last month"
- Complex: Your SQL Warehouse cost query

**Tip 2: Check Databricks UI**
After asking a query in your Streamlit app, check the same conversation in Databricks UI Genie Space. Does the UI show suggested questions? If yes, but your app logs say `False`, that's a critical clue!

**Tip 3: Compare Timestamps**
If you see suggested questions in Databricks UI but not in logs, make sure you're checking the same conversation (same timestamp).

---

## 🆘 Troubleshooting

### **No Logging Output Appears**

**Problem:** Terminal is silent after query.

**Solutions:**
1. Check terminal is the one running `streamlit run app.py`
2. Verify logging module imported (check for errors on startup)
3. Check `genie_app.log` file was created

### **"Permission Denied" on Log File**

**Problem:** Can't write to `genie_app.log`.

**Solution:**
```bash
# Check file permissions
ls -la genie_app.log

# Remove if needed
rm genie_app.log

# Restart app
streamlit run app.py
```

### **Log Output is Garbled**

**Problem:** Terminal encoding issues.

**Solution:**
```bash
# Read the log file instead
cat genie_app.log | tail -50
```

---

## 🚀 Ready to Test!

Run this now:
```bash
streamlit run app.py
```

Ask your test query, watch the terminal, and share the logging output!

This will tell us exactly what's happening with the API fields. 🎯
