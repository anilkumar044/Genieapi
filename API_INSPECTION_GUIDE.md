# API Response Inspection Guide

## 🎯 Purpose

Before we add more features, let's **inspect your actual API responses** to see exactly what fields Databricks Genie returns with YOUR data and YOUR queries.

This ensures we only add fields that:
- ✅ Actually exist in responses
- ✅ Have real values (not always null/empty)
- ✅ Are useful to display

---

## 🔍 Two Ways to Inspect

### **Method 1: Standalone Inspector Script** (Recommended)

**When to use:** Get a complete dump of all response fields

**How to run:**
```bash
python inspect_api_response.py
```

**What it does:**
1. Connects to your Databricks workspace
2. Sends a test query to Genie
3. Shows EVERY field in the response
4. Shows nested object structures
5. Shows which fields have values vs null

**What you'll see:**
```json
{
  "id": {
    "type": "str",
    "is_none": false,
    "has_value": true,
    "value": "abc123..."
  },
  "status": {
    "type": "MessageStatus",
    "is_none": false,
    "has_value": true,
    "value": "COMPLETED"
  },
  "suggested_questions": {
    "type": "GenieSuggestedQuestionsAttachment",
    "is_none": false,
    "has_value": true,
    "nested_fields": ["questions", "title"]
  }
}
```

---

### **Method 2: In-App Debug Mode** (Quick Check)

**When to use:** Check fields during normal app usage

**How to enable:**
1. Run the Streamlit app: `streamlit run app.py`
2. Open sidebar
3. Go to "Advanced" section
4. Check "Debug Mode"
5. Ask any question

**What you'll see:**
```
🔍 DEBUG - Complete Response Structure:

Message Fields:
- id: abc123...
- conversation_id: def456...
- status: COMPLETED
- created_timestamp: 1234567890
- last_updated_timestamp: 1234567900
- user_id: 12345
- error: None
- feedback: None

Attachment 1 Fields:
- id: xyz789...
- Has text: True
- Has query: True
- Has suggested_questions: True  ← FOUND IT!
- Has query_result_metadata: True

Query Fields:
- title: Top 10 Warehouses  ← FOUND IT!
- description: Calculates...
- statement_id: stmt_abc...  ← FOUND IT!
- last_updated_timestamp: 1234567900

Suggested Questions Available: Yes  ← FOUND IT!

Query Result Metadata:
- row_count: 42
- truncated: False

---

[Then your normal response...]
```

---

## 📝 What to Look For

When inspecting responses, pay attention to:

### ✅ **Fields That Have Values**
```
"has_value": true
```
These are candidates for display!

### ❌ **Fields That Are Always Null**
```
"is_none": true
```
Don't bother displaying these.

### 🎯 **Key Fields to Check**

**Priority 1: Must Verify**
- [ ] `suggested_questions` - Does it exist? Does it have questions?
- [ ] `created_timestamp` + `last_updated_timestamp` - Are they present?
- [ ] `response.error` - Does it appear when queries fail?
- [ ] `query.title` - Is it populated?

**Priority 2: Good to Know**
- [ ] `query.statement_id` - Is it there?
- [ ] `query_result_metadata.row_count` - Always present?
- [ ] `status` - What values do you see?
- [ ] `manifest.total_row_count` - In query results?

**Priority 3: Nice to Have**
- [ ] `feedback` - Ever populated?
- [ ] `user_id` - What does it show?
- [ ] `query.last_updated_timestamp` - Present?

---

## 🧪 Test Queries to Try

Run the inspector with different types of queries:

### **1. Simple Query**
```
"Show me sample data"
```
Check: Basic response structure

### **2. Aggregation Query**
```
"Show me top 10 customers by revenue"
```
Check: Row counts, suggested questions

### **3. Time-based Query**
```
"What were sales last month?"
```
Check: Suggested follow-ups

### **4. Complex Query**
```
"Calculate SQL Warehouse usage costs for warehouse_id in ('abc', 'def') between 2025-10-01 and 2025-11-10"
```
Check: All metadata fields, query title

### **5. Error-Inducing Query** (Optional)
```
"Show me data from table_that_doesnt_exist"
```
Check: Error field structure

---

## 📊 Analysis Checklist

After running inspections, answer these:

### **Suggested Questions**
- [ ] Does `suggested_questions` field exist?
- [ ] Is it ever populated (not null)?
- [ ] How many questions are typically suggested?
- [ ] What's the structure? (Array of strings? Object?)

### **Query Title**
- [ ] Does `query.title` exist?
- [ ] Is it different from `query.description`?
- [ ] Is it populated for all queries?
- [ ] Is it useful/concise?

### **Timestamps**
- [ ] Are `created_timestamp` and `last_updated_timestamp` present?
- [ ] What format are they? (Unix timestamp? ISO string?)
- [ ] Can we calculate response time reliably?

### **Statement ID**
- [ ] Does `query.statement_id` exist?
- [ ] Is it always populated when there's a query?
- [ ] Can we use it for re-execution?

### **Row Counts**
- [ ] Does `query_result_metadata.row_count` exist?
- [ ] Does `manifest.total_row_count` exist (in query results)?
- [ ] Are they different? (shown vs total)
- [ ] Is `truncated` flag reliable?

### **Error Handling**
- [ ] What does `response.error` look like when populated?
- [ ] Does it have a message? Error code?
- [ ] Is it structured or just a string?

---

## 🎯 Decision Matrix

Based on inspection results, decide what to add:

| Feature | If Found | If Not Found | If Sometimes |
|---------|----------|--------------|--------------|
| **Suggested Questions** | ✅ Add! | ❌ Skip | 🤔 Add with null check |
| **Query Title** | ✅ Add! | ❌ Skip | 🤔 Fall back to description |
| **Response Time** | ✅ Add! | ❌ Skip | 🤔 Show when available |
| **Statement ID** | ✅ Add re-run | ❌ Skip | 🤔 Show when present |
| **Pagination Info** | ✅ Add! | ❌ Skip | 🤔 Show when truncated |

---

## 📋 Next Steps

### **Step 1: Run Inspector**
```bash
python inspect_api_response.py
```

### **Step 2: Share Results**
Tell me what you found:
- "Suggested questions: YES, has array of 3 questions"
- "Query title: YES, shows 'Top 10 Customers'"
- "Timestamps: YES, Unix format"
- "Statement ID: YES, looks like 'stmt_abc123...'"

### **Step 3: We Add Features**
Based on what's ACTUALLY in your responses, I'll implement:
1. ✅ Suggested follow-up questions (if present)
2. ✅ Response time (if timestamps present)
3. ✅ Query title (if present and useful)
4. ✅ Pagination info (if row counts present)
5. ✅ Error messages (if error field structured)
6. ✅ Re-run query button (if statement_id present)

---

## 💡 Tips

**Tip 1: Run with Different Queries**
Different query types might return different fields

**Tip 2: Check for Consistency**
Run same query multiple times - are fields consistent?

**Tip 3: Look at Actual Values**
Don't just check if field exists - check if value is useful

**Tip 4: Compare with Databricks UI**
What does Databricks UI show that we're not showing?

---

## 🚦 Current Status

### **What We Know from Docs:**
- ✅ `suggested_questions` - Documented as available
- ✅ `query.title` - Documented as available
- ✅ Timestamps - Documented as available
- ✅ `statement_id` - Documented as available
- ✅ Error field - Documented as available

### **What We Need to Verify:**
- ❓ Are these fields ACTUALLY populated in real responses?
- ❓ Are they populated CONSISTENTLY?
- ❓ Are the values USEFUL for display?
- ❓ What's the exact structure when populated?

---

## ⚠️ Important Notes

1. **Don't trust docs alone** - Inspect real responses
2. **Your queries matter** - Different queries = different fields
3. **Null checks required** - Always check if fields exist before displaying
4. **Version matters** - API in Public Preview, fields may vary

---

## 🎬 Ready to Inspect?

Run this now:
```bash
python inspect_api_response.py
```

Or enable debug mode in the app and ask a few questions.

Then tell me:
1. What fields are present?
2. What fields have useful values?
3. What surprised you?

We'll add the features that make sense based on REAL data! 🚀
