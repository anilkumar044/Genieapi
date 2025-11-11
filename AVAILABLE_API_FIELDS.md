# Genie API Response Fields - Complete Analysis

## 🔍 What We're Currently Displaying

✅ **attachment.text.content** - Natural language answer
✅ **attachment.query.description** - What the SQL does
✅ **attachment.query.query** - The SQL query
✅ **attachment.query_result_metadata.row_count** - Number of rows
✅ **attachment.query_result_metadata.truncated** - If results were cut off
✅ **Data table** - The actual result data

---

## 📦 What's Available But NOT Displayed

### **Category 1: Suggested Follow-up Questions** 🌟 **HIGH VALUE!**

**Field:** `attachment.suggested_questions`

**What it is:** AI-generated follow-up questions based on the current query

**Example:**
```json
{
  "suggested_questions": [
    "Show me the trend over the last 6 months",
    "Break this down by region",
    "What's the average cost per warehouse?"
  ]
}
```

**Why useful:**
- Guides users on what to ask next
- Improves UX by suggesting logical follow-ups
- Helps users explore data they didn't know to ask about

**Display as:** Buttons or links below the response

---

### **Category 2: Query Metadata** 🌟 **MEDIUM-HIGH VALUE**

#### **2.1 Query Title**
**Field:** `attachment.query.title`

**What it is:** A short title describing the query

**Example:** "Top 10 SQL Warehouses by Cost"

**Why useful:**
- Quick summary of what the query does
- Can be used for bookmarking/favorites
- Better than description for quick reference

#### **2.2 Statement ID**
**Field:** `attachment.query.statement_id`

**What it is:** ID for the executed SQL statement

**Why useful:**
- Can re-execute the same query
- Can check query history
- Can get execution metrics (duration, warehouse used)

**Display as:** "Re-run Query" button or execution details

#### **2.3 Last Updated Timestamp**
**Field:** `attachment.query.last_updated_timestamp`

**What it is:** When the query was last updated

**Why useful:**
- Shows data freshness
- Helps understand if results are stale

**Display as:** "Last updated: 2 hours ago"

---

### **Category 3: Timestamps** 🌟 **MEDIUM VALUE**

#### **3.1 Message Timestamps**
**Fields:**
- `response.created_timestamp` - When processing started
- `response.last_updated_timestamp` - When processing finished

**Why useful:**
- Calculate query execution time
- Show "Answered in 12.5 seconds"
- Performance transparency

**Display as:** "⏱️ Response time: 12.5 seconds"

---

### **Category 4: Processing Status** 🌟 **MEDIUM VALUE**

**Field:** `response.status`

**Values:**
- `SUBMITTED` - Just received
- `FETCHING_METADATA` - Getting data source info
- `FILTERING_CONTEXT` - Finding relevant tables/columns
- `ASKING_AI` - Waiting for LLM
- `PENDING_WAREHOUSE` - Waiting for compute
- `EXECUTING_QUERY` - Running SQL
- `COMPLETED` - Done!
- `FAILED` - Error occurred

**Why useful:**
- Show real-time progress
- Better than generic "thinking" spinner
- Educates users on what Genie is doing

**Display as:** Progress indicator with status text

---

### **Category 5: Schema Information** 🌟 **MEDIUM VALUE**

**Field:** `statement_response.manifest.schema.columns`

**What it is:** Column names and data types

**Example:**
```json
{
  "columns": [
    {"name": "warehouse_id", "type_name": "STRING"},
    {"name": "total_dbu", "type_name": "DECIMAL(10,2)"},
    {"name": "usage_date", "type_name": "DATE"}
  ]
}
```

**Why useful:**
- Shows data types (helps understand the data)
- Can color-code columns by type
- Technical users appreciate this

**Display as:** Table header with data types or tooltip on hover

---

### **Category 6: Pagination Info** 🌟 **LOW-MEDIUM VALUE**

**Fields:**
- `manifest.total_row_count` - Total rows in result
- `manifest.total_chunk_count` - How many chunks
- `manifest.truncated` - If results were limited

**Why useful:**
- Shows if you're seeing all data
- "Showing 100 of 50,000 rows"
- Can offer "Load more" option

**Display as:** Info banner above table

---

### **Category 7: User & Conversation Info** 🌟 **LOW VALUE**

**Fields:**
- `response.user_id` - Who asked the question
- `response.conversation_id` - Conversation identifier
- `response.message_id` - Message identifier

**Why useful:**
- Multi-user scenarios
- Conversation management
- Debugging

**Display as:** Hidden in debug mode or footer

---

### **Category 8: Error Information** 🌟 **HIGH VALUE (when errors occur)**

**Field:** `response.error`

**What it is:** Detailed error message if query failed

**Example:**
```json
{
  "error": {
    "message": "Table 'sales.orders' not found",
    "error_code": "TABLE_NOT_FOUND"
  }
}
```

**Why useful:**
- Better error messages
- Help users fix issues
- Show what went wrong

**Display as:** Error alert with helpful message

---

### **Category 9: Feedback** 🌟 **LOW VALUE**

**Field:** `response.feedback`

**What it is:** User feedback on the response (thumbs up/down)

**Why useful:**
- Show if you've already rated this response
- Community ratings (if shared)

**Display as:** Thumbs up/down buttons

---

## 💎 **Recommended Additions (Priority Order)**

### **🥇 Priority 1: Must Add**

1. **Suggested Follow-up Questions**
   - Huge UX improvement
   - Guides exploration
   - Easy to implement (just display as buttons)

2. **Error Messages**
   - Critical for debugging
   - Show when status = FAILED
   - Better than generic errors

### **🥈 Priority 2: Should Add**

3. **Query Response Time**
   - Calculate from timestamps
   - "⏱️ Answered in 12.5 seconds"
   - Shows performance

4. **Query Title**
   - Short, descriptive name
   - Better than full description
   - Good for UI headers

5. **Pagination Info**
   - "Showing 100 of 50,000 rows"
   - Transparency about limits
   - Option to load more

### **🥉 Priority 3: Nice to Have**

6. **Processing Status**
   - Real-time progress updates
   - Better loading experience
   - Educational

7. **Schema Info (Data Types)**
   - Show column types
   - Technical detail
   - Tooltip or expandable

8. **Statement ID**
   - "Re-run query" button
   - Advanced feature
   - Power user tool

---

## 🎨 **Mockup: Enhanced Response Display**

```
[Natural Language Answer from Genie]

Query Title: Top SQL Warehouses by Cost
Query Description: Calculates total DBU usage for specified warehouses

Generated SQL:
```sql
SELECT warehouse_id, SUM(usage_quantity)...
```

📊 Results: Showing 42 of 42 rows | ⏱️ Answered in 8.2 seconds

[Interactive Data Table with Schema]
| warehouse_id (STRING) | total_dbu (DECIMAL) | usage_date (DATE) |
|----------------------|---------------------|-------------------|
| ...                  | ...                 | ...               |

💡 **Suggested follow-up questions:**
[Show me the trend over time] [Break down by region] [What's the average?]

[Re-run Query] [Download CSV] [👍 0  👎 0]
```

---

## 📊 **Implementation Complexity vs Value**

| Feature | Value | Complexity | Priority |
|---------|-------|------------|----------|
| Suggested Questions | ⭐⭐⭐⭐⭐ | Low | 🥇 Must |
| Error Messages | ⭐⭐⭐⭐⭐ | Low | 🥇 Must |
| Response Time | ⭐⭐⭐⭐ | Low | 🥈 Should |
| Query Title | ⭐⭐⭐⭐ | Low | 🥈 Should |
| Pagination Info | ⭐⭐⭐⭐ | Low | 🥈 Should |
| Processing Status | ⭐⭐⭐ | Medium | 🥉 Nice |
| Schema Types | ⭐⭐⭐ | Low | 🥉 Nice |
| Statement ID/Re-run | ⭐⭐⭐ | Medium | 🥉 Nice |
| Feedback UI | ⭐⭐ | Medium | 💤 Later |
| User/Conv IDs | ⭐ | Low | 💤 Later |

---

## 🚀 **Quick Wins**

These are **easy to add** and **high value**:

1. **Suggested Questions** - Just check if field exists and display as buttons
2. **Query Title** - One line: display `attachment.query.title` if exists
3. **Response Time** - `(last_updated - created) / 1000` seconds
4. **Error Display** - Check `response.error` and show with `st.error()`
5. **Row Count** - Display `manifest.total_row_count` vs actual rows shown

---

## 💡 **Recommendation for Your Demo**

For a **2-day demo**, add these **4 features**:

1. ✅ **Suggested Follow-up Questions** - Amazing UX, easy to implement
2. ✅ **Query Response Time** - Shows performance, very simple
3. ✅ **Error Messages** - Critical for reliability, easy check
4. ✅ **Pagination Info** - Transparency, one-liner

**Total implementation time:** 1-2 hours
**Value added:** Huge improvement in UX and professionalism

---

## 📝 **Code Snippets**

### **1. Suggested Questions**
```python
# In format_genie_response()
if hasattr(attachment, 'suggested_questions') and attachment.suggested_questions:
    formatted_text += "\\n💡 **Suggested follow-ups:**\\n"
    # Will be displayed as buttons in display_query_results()
```

### **2. Response Time**
```python
# In format_genie_response()
if response.created_timestamp and response.last_updated_timestamp:
    duration = (response.last_updated_timestamp - response.created_timestamp) / 1000
    formatted_text += f"⏱️ **Response time:** {duration:.1f} seconds\\n\\n"
```

### **3. Error Display**
```python
# In main()
if response and response.error:
    st.error(f"❌ **Query Failed:** {response.error.message}")
```

### **4. Pagination Info**
```python
# In display_query_results()
if manifest.total_row_count > len(rows):
    st.info(f"📊 Showing {len(rows)} of {manifest.total_row_count} total rows")
```

---

## ✅ **Summary**

**Currently displaying:** 6 fields
**Available but not displayed:** ~15 fields
**Recommended to add:** 4 high-value, low-effort fields

**Next steps:**
1. Add suggested follow-up questions (biggest win!)
2. Show response time (performance transparency)
3. Better error handling (reliability)
4. Pagination info (data transparency)

These additions will make your app significantly more professional and user-friendly with minimal effort!
