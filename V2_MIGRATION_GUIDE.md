# 🚀 App V2 Migration Guide - Direct REST API Implementation

## 🔍 The Problem We Found

You discovered through Bruno/Postman testing that **we were missing a critical API call**!

### ❌ Old Implementation (app.py with SDK)

```
1. POST /start-conversation → Get message_id, conversation_id
2. ❌ MISSING: GET /messages/{message_id} → Get FULL message details
3. GET /query-result → Try to get data (but missing attachment_id!)
```

**Result:** Incomplete data, missing attachments, no query descriptions showing properly.

### ✅ New Implementation (app_v2.py with direct REST)

```
1. POST /start-conversation → Get message_id, conversation_id
2. ✅ GET /messages/{message_id} → Get FULL message details with:
   - attachments[].id (attachment_id)
   - attachments[].query.query (SQL)
   - attachments[].query.description
   - attachments[].text.content (natural language response)
   - row_count
3. GET /query-result → Get actual data using correct attachment_id
```

**Result:** Complete data, all fields available, proper flow!

---

## 📋 Your API Testing Results (Bruno/Postman)

You tested these 4 APIs and confirmed they work:

### **API 1: Start Conversation**
```
POST /api/2.0/genie/spaces/{space_id}/start-conversation
Body: {"content": "your query"}
Returns: message_id, conversation_id, status
```

### **API 2: Get Message Details** ← **THE MISSING ONE!**
```
GET /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}
Returns: Complete message with attachments, SQL, descriptions, attachment_id
```

### **API 3: Get Query Result**
```
GET /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}/attachments/{attachment_id}/query-result
Returns: statement_response, manifest (columns, row_count), result (data_typed_array)
```

### **API 4: Send Follow-up Message**
```
POST /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages
Body: {"content": "follow-up query"}
Returns: new message_id
```

---

## 🎯 What's New in V2

### **1. Direct REST API Calls**
- Uses `requests` library instead of `databricks-sdk`
- Complete control over API calls
- No SDK abstraction hiding data

### **2. Three-Tab Interface**

#### **Tab 1: 🗂️ Spaces**
- Lists all Genie spaces in your workspace
- Click "Select Space" to work with a space
- Shows space name, description, ID

#### **Tab 2: 💬 Conversations**
- Shows conversations in the selected space
- Load existing conversations (if list API exists)
- View conversation history

#### **Tab 3: 🧞 Chat**
- Start new conversations
- Ask questions and get responses
- **"Show Query Results" button** - Click to fetch actual data
- Follow-up questions maintain context
- See SQL, descriptions, and data tables

### **3. Proper API Flow**
```
User asks question
    ↓
POST start-conversation (or send_message)
    ↓
GET message/{message_id} ← Get full details!
    ↓
Extract: SQL, description, attachment_id
    ↓
User clicks "Show Query Results"
    ↓
GET query-result → Display data table
```

---

## 🚀 How to Use V2

### **Step 1: Install Dependencies**
```bash
pip install -r requirements.txt
```

### **Step 2: Configure .env**
Your existing `.env` file works as-is:
```
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=dapiXXXXXXXXXXXXXXXXXXXXXX
```

Note: `GENIE_SPACE_ID` is no longer needed in .env - you select it in the UI!

### **Step 3: Run V2**
```bash
streamlit run app_v2.py
```

### **Step 4: Select a Space**
1. Go to **"🗂️ Spaces"** tab
2. See all available Genie spaces
3. Click **"Select Space"** on the space you want to use

### **Step 5: Start Chatting**
1. Go to **"🧞 Chat"** tab
2. Type your question in the chat input
3. Wait for Genie's response
4. You'll see:
   - Natural language response (if available)
   - Query description
   - SQL code
   - **"📊 Show Query Results"** button

### **Step 6: View Data**
1. Click **"📊 Show Query Results"** button
2. App fetches actual data from API 3
3. See:
   - Pagination info ("Showing X of Y rows")
   - Full data table
   - Column headers

### **Step 7: Ask Follow-ups**
1. Type a follow-up question
2. Genie maintains conversation context
3. Repeat process

---

## 🔍 Key Differences from V1

| Feature | V1 (app.py + SDK) | V2 (app_v2.py + REST) |
|---------|-------------------|----------------------|
| API Client | databricks-sdk | requests library |
| Space Selection | .env file only | UI + multiple spaces |
| API Flow | Missing GET message | Complete flow |
| Data Fetching | Automatic attempt | User-triggered button |
| Attachment ID | Guessed/missing | Correctly extracted |
| Error Handling | SDK exceptions | HTTP status codes |
| Field Availability | Some fields missing | All fields from API |

---

## 📊 Expected UI Flow

### **Spaces Tab**
```
🗂️ Genie Spaces
Found 3 space(s)

📁 Sales Analytics
   Sales data analysis space
   Space ID: 01ABC...
   [Select Space]

📁 Marketing Insights
   Marketing metrics and trends
   Space ID: 01DEF...
   [Select Space]
```

### **Chat Tab (After Asking Question)**
```
🧞 Chat with Genie: Sales Analytics
✅ Active Conversation: 01f0bf16002aldff8c92dal608ea19b5

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You:
Calculate SQL Warehouse usage costs for warehouse_id in ('abc123') between 2025-10-01 and 2025-11-10

Genie:
✅ Query processed successfully!

ℹ️ Query Description: You're looking to calculate the total usage cost for specific SQL warehouses over a defined date range.

```sql
SELECT warehouse_id, SUM(usage_quantity) as total_usage
FROM system.billing.usage
WHERE warehouse_id IN ('abc123')
AND usage_date BETWEEN '2025-10-01' AND '2025-11-10'
GROUP BY warehouse_id
```

[📊 Show Query Results]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(User clicks "Show Query Results" button)

ℹ️ Showing 1 of 1 total rows

| warehouse_id | total_usage |
|--------------|-------------|
| abc123       | 1234.56     |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(User asks follow-up)

You:
Show only costs greater than 1000

Genie:
✅ Query processed successfully!
(Shows updated SQL with WHERE clause and new results)
```

---

## 🛠️ Technical Implementation Details

### **GenieAPIClient Class**

```python
class GenieAPIClient:
    def __init__(self, host: str, token: str):
        self.base_url = f"{host}/api/2.0/genie"
        self.headers = {"Authorization": f"Bearer {token}"}

    def _make_request(self, method: str, endpoint: str, **kwargs):
        # Direct HTTP calls with requests library
        url = f"{self.base_url}{endpoint}"
        response = requests.request(method, url, headers=self.headers, **kwargs)
        return response.json()
```

### **Critical Method: get_message()**

This is the one we were missing!

```python
def get_message(self, space_id: str, conversation_id: str, message_id: str):
    """Get FULL message details including attachments"""
    return self._make_request(
        "GET",
        f"/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}"
    )
```

### **Data Parsing Function**

```python
def parse_query_result(result_data: Dict) -> Optional[pd.DataFrame]:
    """Parse query result into pandas DataFrame"""
    # Extracts:
    # - Column names from manifest.schema.columns
    # - Data from result.data_typed_array
    # - Pagination info from manifest.total_row_count, truncated
    # Returns: df, total_rows, truncated
```

---

## 🧪 Testing Checklist

After running V2, verify:

### **✅ Spaces Tab**
- [ ] Lists all Genie spaces
- [ ] Shows space names and IDs
- [ ] "Select Space" button works
- [ ] Selected space appears in sidebar

### **✅ Chat Tab**
- [ ] Can ask questions
- [ ] See query description
- [ ] See SQL code
- [ ] "Show Query Results" button appears
- [ ] Clicking button fetches data
- [ ] Data table displays correctly
- [ ] Pagination info shows ("X of Y rows")
- [ ] Follow-up questions work
- [ ] Conversation ID maintained

### **✅ Data Accuracy**
- [ ] Same results as Bruno/Postman testing
- [ ] All columns present
- [ ] Data types correct
- [ ] Row counts match

---

## 🐛 Troubleshooting

### **"Missing credentials in .env file"**
- Check `.env` file exists in project root
- Verify `DATABRICKS_HOST` and `DATABRICKS_TOKEN` are set
- No need for `GENIE_SPACE_ID` in V2!

### **"HTTP Error: 401"**
- Token expired - generate new token in Databricks
- Update `DATABRICKS_TOKEN` in `.env`
- Restart the app

### **"HTTP Error: 404 - Space not found"**
- Space ID might be wrong
- Use the Spaces tab to see available spaces
- Click "Select Space" instead of hardcoding

### **"No data available to display"**
- Query might have returned 0 rows
- Check if query succeeded in Databricks UI
- Try a simpler query: "Show me sample data"

### **"Show Query Results" button does nothing**
- Check browser console for errors
- Verify attachment_id was extracted from message
- Check sidebar Debug Info for conversation_id and message_id

### **Conversations Tab shows "No conversations found"**
- This is normal! The list conversations API might not be available
- Conversations are still working - just not listed
- Use the Chat tab to start new conversations

---

## 📊 API Response Comparison

### **What V1 SDK was giving us:**
```json
{
  "id": "msg_123",
  "conversation_id": "conv_456",
  "status": "COMPLETED",
  "attachments": [
    // Incomplete or missing attachment data
  ]
}
```

### **What V2 REST gives us (via get_message):**
```json
{
  "id": "msg_123",
  "conversation_id": "conv_456",
  "status": "COMPLETED",
  "attachments": [
    {
      "id": "attachment_789",  ← We need this!
      "text": {
        "content": "Here's the query..."
      },
      "query": {
        "query": "SELECT ...",
        "description": "You're looking to calculate...",
        "statement_id": "01f0bf16-18a4-17c4-8eb8-e8b4617cd6fd"
      }
    }
  ]
}
```

---

## 🎯 Next Steps

### **1. Test V2**
```bash
streamlit run app_v2.py
```

### **2. Compare with Your Bruno Tests**
- Ask the same queries you tested in Bruno
- Verify you get the same data
- Check that all fields are now available

### **3. Report Findings**
Let me know:
- Does data show correctly now?
- Do you see pagination info?
- Are descriptions showing?
- Any errors or missing features?

### **4. Future Enhancements**
Possible additions:
- ✅ Export data to CSV
- ✅ Query history within a space
- ✅ Conversation search
- ✅ Share conversations
- ✅ Query templates
- ✅ Dark mode

---

## 📁 File Structure

```
Genieapi/
├── app.py                      # Old version (SDK-based)
├── app_v2.py                   # New version (REST API) ⭐
├── requirements.txt            # Updated with requests
├── .env                        # Credentials (same as before)
├── V2_MIGRATION_GUIDE.md      # This file
├── POSTMAN_API_COLLECTION.md  # API reference
└── LOGS_LOCATION.md           # Logging guide (for debugging)
```

---

## 🔄 Migration Path

**Keep both versions for now:**

### **Use V1 (app.py) if:**
- You want the simpler single-file approach
- You don't need all API fields
- You're okay with SDK abstractions

### **Use V2 (app_v2.py) if:** ⭐
- You need complete API data
- You want to work with multiple spaces
- You want control over data fetching
- You need the exact API flow you tested in Bruno

**Recommendation:** Use V2 for your demo! It matches exactly what you tested and confirmed working.

---

## 🎉 Summary

### **The Root Cause:**
The databricks-sdk's `start_conversation_and_wait()` doesn't return complete message details. We needed to call `GET /messages/{message_id}` separately to get attachments with proper IDs.

### **The Solution:**
V2 app with direct REST API calls following the exact flow you confirmed working in Bruno:
1. Start/send conversation
2. **Get message details** ← The critical step!
3. Extract attachment_id
4. Fetch query results when user clicks button

### **The Result:**
✅ Complete data access
✅ All API fields available
✅ Matches your Bruno testing
✅ Ready for demo!

---

## 🚀 Ready to Test!

```bash
streamlit run app_v2.py
```

1. Select a space from the Spaces tab
2. Go to Chat tab
3. Ask your SQL Warehouse cost query
4. Click "Show Query Results"
5. Verify you see the same data as in Bruno!

Let me know how it works! 🎯