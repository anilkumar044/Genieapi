# Databricks Genie API - Complete Reference & Analysis

## 📋 Executive Summary

**Your Question:** "Why is there a 'Retrieve generated SQL API'? Does that mean when I ask a question I don't get the SQL output in the response? Do I need to call a separate API for that?"

**Answer:** **NO, you DON'T need a separate API call for basic SQL!** The SQL query is included in the response attachments when using `create_message_and_wait()` or `start_conversation_and_wait()`. However, there ARE separate APIs for:
1. **Re-executing** existing queries (without asking Genie again)
2. **Getting full result data** (when you want the actual data rows, not just SQL)
3. **Advanced operations** like feedback, deletion, and conversation management

---

## 🗂️ Complete Genie API Endpoints (2025 Public Preview)

### **Category 1: Spaces Management**

| Endpoint | Method | Purpose | When to Use |
|----------|--------|---------|-------------|
| `/api/2.0/genie/spaces` | GET | List all Genie spaces | Multi-space selector, space discovery |
| `/api/2.0/genie/spaces/{id}` | GET | Get space details | Show space name, description, warehouse |
| `/api/2.0/genie/spaces/{id}` | DELETE | Delete a space | Admin operations (NEW in 2025) |

---

### **Category 2: Conversation Management**

| Endpoint | Method | Purpose | When to Use |
|----------|--------|---------|-------------|
| `POST /api/2.0/genie/spaces/{space_id}/start-conversation` | POST | Start new conversation | First question in a topic |
| `GET /api/2.0/genie/spaces/{space_id}/conversations` | GET | List all conversations | Conversation history feature |
| `GET /api/2.0/genie/spaces/{space_id}/conversations/{id}` | GET | Get conversation details | Load saved conversation |
| `DELETE /api/2.0/genie/spaces/{space_id}/conversations/{id}` | DELETE | Delete conversation | Cleanup, privacy (NEW in 2025) |

---

### **Category 3: Message Management** (Core APIs)

| Endpoint | Method | Purpose | What You Get in Response |
|----------|--------|---------|--------------------------|
| `POST /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages` | POST | Send a message/question | Returns `message_id`, `conversation_id`, initial status |
| `GET /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}` | GET | Poll message status | Returns status + **attachments** when COMPLETED |
| `GET /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages` | GET | Get all messages | Full conversation history |
| `DELETE /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{id}` | DELETE | Delete a message | Cleanup (NEW in 2025) |

**Key Point:** When status = "COMPLETED", the response includes `attachments[]` array with:
- `attachment.text.content` - Natural language response
- `attachment.query.query` - The generated SQL ✅ **YES, SQL IS INCLUDED!**
- `attachment.query.description` - Query explanation
- `attachment_id` - For retrieving result data

---

### **Category 4: Query Result Operations** (Advanced)

| Endpoint | Method | Purpose | When to Use |
|----------|--------|---------|-------------|
| `GET /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}/query-result/{attachment_id}` | GET | Get query result data | When you want the **actual data rows** (not just SQL) |
| `execute_message_attachment_query()` | POST | Re-execute a previous query | Run the same SQL again without asking Genie |

**Key Point:** This is for getting the **data**, not the SQL. The SQL is already in the message response!

---

### **Category 5: Feedback & Enhancement** (NEW in 2025)

| API | Purpose | When to Use |
|-----|---------|-------------|
| Thumbs up/down feedback API | Collect user feedback on responses | Quality improvement, analytics |
| Suggested follow-up questions API | Get AI-suggested next questions | Guided exploration, UX enhancement |

---

## 🔄 Complete API Workflow - Explained

### **Workflow 1: Simple Question (What we're doing in MVP)**

```python
# Step 1: Ask a question
response = w.genie.start_conversation_and_wait(
    space_id=space_id,
    content="Show me top 10 customers"
)

# Step 2: Process response - SQL IS HERE! ✅
for attachment in response.attachments:
    # Natural language answer
    if attachment.text:
        print(f"Answer: {attachment.text.content}")

    # Generated SQL - YES, IT'S INCLUDED!
    if attachment.query:
        print(f"SQL: {attachment.query.query}")
        print(f"Description: {attachment.query.description}")
```

**What you get:**
- ✅ Natural language response
- ✅ SQL query (if generated)
- ✅ Query description
- ✅ Metadata (row count, etc.)

**What you DON'T automatically get:**
- ❌ The actual data rows (need separate call if you want this)

---

### **Workflow 2: Getting Actual Data (Advanced)**

```python
# Step 1: Ask question and get response with SQL
response = w.genie.start_conversation_and_wait(
    space_id=space_id,
    content="Show me top 10 customers"
)

# Step 2: Get the attachment_id from response
for attachment in response.attachments:
    if attachment.query:
        attachment_id = attachment.id  # ← This is the attachment ID

        # Step 3: Retrieve actual query results (data rows)
        result = w.genie.get_message_attachment_query_result(
            space_id=space_id,
            conversation_id=response.conversation_id,
            message_id=response.id,
            attachment_id=attachment_id
        )

        # Now you have the actual data!
        print(result.statement_response.result.data_typed_array)
```

**Response Structure of Query Result:**
```json
{
  "statement_response": {
    "manifest": {
      "format": "JSON_ARRAY",
      "schema": {
        "columns": [
          {"name": "customer_name", "type_name": "STRING"},
          {"name": "total_revenue", "type_name": "DECIMAL"}
        ],
        "column_count": 2
      },
      "total_row_count": 10,
      "total_chunk_count": 1,
      "truncated": false
    },
    "result": {
      "data_typed_array": [
        {"values": [{"str": "Acme Corp"}, {"str": "125000.50"}]},
        {"values": [{"str": "TechCo"}, {"str": "98000.25"}]}
      ]
    }
  }
}
```

---

### **Workflow 3: Re-executing Existing Query (No Genie AI Call)**

```python
# Instead of asking Genie again, just re-run the same SQL
result = w.genie.execute_message_attachment_query(
    space_id=space_id,
    conversation_id=conversation_id,
    message_id=message_id,
    attachment_id=attachment_id
)

# This executes the same SQL without using Genie AI
# Useful for: refreshing data, pagination, exports
```

---

### **Workflow 4: Manual Polling (If Not Using _and_wait Methods)**

```python
# Step 1: Send message (doesn't wait)
response = w.genie.create_message(
    space_id=space_id,
    conversation_id=conversation_id,
    content="Show me sales trends"
)

message_id = response.id

# Step 2: Poll for completion
import time
max_attempts = 120  # 10 minutes max (120 * 5 seconds)
attempt = 0

while attempt < max_attempts:
    # Poll every 5 seconds
    time.sleep(5)

    status = w.genie.get_message(
        space_id=space_id,
        conversation_id=conversation_id,
        message_id=message_id
    )

    if status.status == "COMPLETED":
        # Process attachments - SQL is here!
        for attachment in status.attachments:
            print(attachment.query.query)
        break
    elif status.status in ["FAILED", "CANCELLED"]:
        print("Query failed!")
        break

    attempt += 1
```

---

## 📊 Response Object Structure (GenieMessage)

```python
GenieMessage {
    id: str                      # message_id
    conversation_id: str         # conversation identifier
    space_id: str               # space identifier
    status: str                 # "IN_PROGRESS" | "COMPLETED" | "FAILED" | "CANCELLED"
    content: str                # Your original question
    created_timestamp: int      # When message was created
    updated_timestamp: int      # Last update time

    attachments: List[GenieAttachment] | None  # NULL until COMPLETED
}

GenieAttachment {
    id: str                     # attachment_id (for getting results)

    # Text response (natural language answer)
    text: TextAttachment {
        content: str            # The answer in plain text
    }

    # Query information (if SQL was generated)
    query: QueryAttachment {
        query: str              # ✅ THE SQL QUERY - IT'S HERE!
        description: str        # Explanation of what query does
        statement_id: str       # For re-execution
    }

    # Query metadata
    query_result_metadata: {
        row_count: int          # How many rows returned
        truncated: bool         # If results were truncated
    }
}
```

---

## 🎯 What We Can Incorporate in Our App

### **Currently Implemented (MVP)**
✅ `start_conversation_and_wait()` - Start new conversations
✅ `create_message_and_wait()` - Send follow-up questions
✅ Display `attachment.text.content` - Natural language answers
✅ Display `attachment.query.query` - Show generated SQL

### **Easy Additions (Day 2)**
🟡 **List Spaces** - Let users switch between different Genie spaces
🟡 **Show Query Description** - Display `attachment.query.description`
🟡 **Show Row Counts** - Display `query_result_metadata.row_count`
🟡 **Conversation History** - List and load past conversations

### **Medium Additions (Week 2)**
🟠 **Get Actual Data** - Use `get_message_attachment_query_result()` to show tables
🟠 **Data Visualization** - Parse data and create charts
🟠 **Export Results** - Download data as CSV/Excel
🟠 **Re-execute Queries** - Refresh data without re-asking

### **Advanced Additions (Future)**
🔴 **Suggested Follow-ups** - Show AI-suggested next questions
🔴 **User Feedback** - Thumbs up/down on responses
🔴 **Conversation Management** - Save/delete/organize conversations
🔴 **Multi-space Chat** - Parallel questions across multiple spaces

---

## 🚨 Important Clarifications

### **Myth: You need a separate API call to get SQL**
❌ **FALSE!** The SQL is included in `attachment.query.query` when you use `_and_wait()` methods or poll until COMPLETED.

### **Reality: Separate APIs are for:**
✅ Getting the **actual data rows** (not just SQL)
✅ **Re-executing** queries without asking Genie again
✅ **Management** operations (delete, feedback, etc.)

### **What `_and_wait()` Does**
The `create_message_and_wait()` and `start_conversation_and_wait()` methods:
1. Send your question
2. **Automatically poll** every few seconds
3. Wait until status = "COMPLETED" (up to 20 minutes)
4. Return the **complete response with attachments** (including SQL!)

It's a convenience wrapper that does the polling for you!

---

## 🔍 Rate Limits & Best Practices

| Metric | Limit | Notes |
|--------|-------|-------|
| POST requests | ~5 queries/min/workspace | Sending questions to Genie |
| GET requests | Unlimited | Polling doesn't count! |
| Polling interval | 5-10 seconds | Recommended by Databricks |
| Max polling time | 10 minutes | Most queries finish in 30-60s |
| `_and_wait()` timeout | 20 minutes | Default SDK timeout |

---

## 💡 Recommendations for Our App

### **Keep in MVP (Already Done)**
- ✅ Use `_and_wait()` methods (simplest)
- ✅ Show SQL in responses
- ✅ Show text responses
- ✅ Error handling

### **Add Next (Quick Wins)**
1. **Display row counts** - Show how many rows returned
2. **Show query descriptions** - Explain what SQL does
3. **Space selector** - Let users pick different spaces
4. **Better formatting** - Pretty-print SQL with syntax highlighting

### **Add Later (Value-Add)**
1. **Data tables** - Fetch and display actual data
2. **Charts** - Visualize numeric results
3. **Export** - Download data/SQL
4. **Query library** - Save favorite queries

### **NOT Needed for Demo**
- ❌ Manual polling (SDK handles it)
- ❌ Conversation persistence (session state is fine)
- ❌ Re-execution APIs (just ask again for demo)
- ❌ Feedback APIs (nice-to-have)

---

## 📝 Summary: Answering Your Questions

**Q: Why is there a "Retrieve generated SQL API"?**
**A:** There isn't! The confusion comes from:
- `get_message_attachment_query_result()` retrieves **DATA**, not SQL
- `execute_message_attachment_query()` **re-runs** an existing query
- The SQL itself comes in the standard message response!

**Q: Does that mean when I ask a question I don't get the SQL output in response?**
**A:** **NO!** You DO get the SQL in the response, in `attachment.query.query`

**Q: Do I need to call a separate API for that?**
**A:** **NO!** You only need separate calls if you want:
- The actual **data rows** (not just the SQL)
- To **re-execute** an old query without asking Genie again

---

## ✅ Action Items

1. **Keep current implementation** - It's correct!
2. **Add SQL syntax highlighting** - Make SQL pretty
3. **Show query metadata** - Row counts, descriptions
4. **Consider data fetching** - If you want to show actual tables
5. **Test with real queries** - Verify SQL is appearing

---

**Bottom Line:** Our MVP is already using the right APIs! The `_and_wait()` methods handle everything including returning the SQL. We don't need additional API calls for basic functionality.
