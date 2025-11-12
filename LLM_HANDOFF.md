# 🤖 LLM Handoff Document - Databricks Genie API Integration

**Project:** Streamlit app for Databricks Genie API
**Current Status:** V2 implementation complete, ready for testing
**Last Updated:** 2025-11-12

---

## 📋 Project Context

### **Goal**
Create a Streamlit application that integrates with Databricks Genie API to:
- List and select Genie spaces
- Ask natural language questions
- Display generated SQL
- Fetch and show actual query results
- Support follow-up questions with conversation context

### **Timeline**
- Demo in 2 days
- MVP approach required

---

## 🔍 Problem Discovery

### **Initial Approach (FAILED)**
- Used `databricks-sdk` Python library
- SDK's `start_conversation_and_wait()` method
- **Problem:** Incomplete data, missing attachment IDs, couldn't fetch query results

### **User Testing (SUCCESS)**
User tested APIs directly in Bruno/Postman and confirmed **all 4 APIs work correctly**:

1. ✅ POST `/api/2.0/genie/spaces/{space_id}/start-conversation`
2. ✅ GET `/api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}` ← **THE CRITICAL ONE!**
3. ✅ GET `/api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}/attachments/{attachment_id}/query-result`
4. ✅ POST `/api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages`

### **Root Cause**
The SDK was abstracting away API #2 (get message details), which contains:
- `attachment_id` (needed for API #3)
- Complete query information
- Text content
- All metadata

---

## 🎯 Complete API Flow (Confirmed Working in Bruno)

### **API 1: Start Conversation**
```http
POST /api/2.0/genie/spaces/{space_id}/start-conversation
Content-Type: application/json
Authorization: Bearer {token}

{
  "content": "Calculate SQL Warehouse usage costs for warehouse_id in ('abc123') between 2025-10-01 and 2025-11-10"
}

RESPONSE:
{
  "message_id": "01f0bf1613dflel7b3ae3b0d9eеa3db4",
  "conversation_id": "01f0bf16002aldff8c92dal608ea19b5",
  "status": "COMPLETED" | "EXECUTING_QUERY" | "FAILED"
}
```

### **API 2: Get Message Details** ⭐ (CRITICAL - Was Missing!)
```http
GET /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}
Authorization: Bearer {token}

RESPONSE:
{
  "id": "01f0bf1613dflel7b3ae3b0d9eеa3db4",
  "conversation_id": "01f0bf16002aldff8c92dal608ea19b5",
  "status": "COMPLETED",
  "attachments": [
    {
      "id": "attachment_abc123",  ← NEED THIS FOR API #3!
      "text": {
        "content": "Natural language response..."
      },
      "query": {
        "query": "SELECT warehouse_id, SUM(usage_quantity) as total_usage FROM ...",
        "description": "You're looking to calculate the total usage cost for specific SQL warehouses over a defined date range.",
        "statement_id": "01f0bf16-18a4-17c4-8eb8-e8b4617cd6fd"
      }
    }
  ],
  "row_count": 156
}
```

**Key Fields from API 2:**
- `attachments[0].id` → attachment_id for API #3
- `attachments[0].query.query` → Generated SQL
- `attachments[0].query.description` → Query explanation
- `attachments[0].text.content` → Natural language response (may be null)

### **API 3: Get Query Results (Actual Data)**
```http
GET /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}/attachments/{attachment_id}/query-result
Authorization: Bearer {token}

RESPONSE:
{
  "statement_response": {
    "status": {
      "state": "SUCCEEDED"
    },
    "manifest": {
      "schema": {
        "columns": [
          {"name": "warehouse_id", "type_name": "STRING", "position": 0},
          {"name": "total_usage", "type_name": "DECIMAL", "position": 1},
          {"name": "total_cost", "type_name": "DECIMAL", "position": 2}
        ]
      },
      "total_row_count": 156,
      "truncated": false
    },
    "result": {
      "data_typed_array": [
        {
          "values": [
            {"str": "abc123"},
            {"double": 1234.56},
            {"double": 456.78}
          ]
        },
        {
          "values": [
            {"str": "def456"},
            {"double": 2345.67},
            {"double": 567.89}
          ]
        }
      ]
    }
  }
}
```

**Key Fields from API 3:**
- `manifest.schema.columns[]` → Column names and types
- `manifest.total_row_count` → Total rows available (for pagination)
- `manifest.truncated` → Whether results are truncated
- `result.data_typed_array[]` → Actual data rows
- Values have types: `str`, `int`, `long`, `double`, `bool`

### **API 4: Send Follow-up Message**
```http
POST /api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages
Content-Type: application/json
Authorization: Bearer {token}

{
  "content": "Show only the top 5 results"
}

RESPONSE:
{
  "message_id": "new_message_id",
  "conversation_id": "01f0bf16002aldff8c92dal608ea19b5",  // Same conversation ID
  "status": "COMPLETED"
}
```

**Then repeat API #2 and API #3 to get the follow-up results.**

---

## 💻 Current Implementation: app_v2.py

### **Architecture**
- Direct REST API calls using `requests` library (no SDK)
- Three-tab Streamlit interface
- Session state for conversation management
- User-triggered data fetching

### **Key Components**

#### **1. GenieAPIClient Class**
```python
class GenieAPIClient:
    def __init__(self, host: str, token: str):
        self.base_url = f"{host}/api/2.0/genie"
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

    def _make_request(self, method: str, endpoint: str, **kwargs):
        """Generic HTTP request handler"""
        url = f"{self.base_url}{endpoint}"
        response = requests.request(method, url, headers=self.headers, **kwargs)
        return response.json()

    # API 1
    def start_conversation(self, space_id: str, content: str):
        return self._make_request("POST", f"/spaces/{space_id}/start-conversation", json={"content": content})

    # API 2 - THE CRITICAL ONE!
    def get_message(self, space_id: str, conversation_id: str, message_id: str):
        return self._make_request("GET", f"/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}")

    # API 3
    def get_query_result(self, space_id: str, conversation_id: str, message_id: str, attachment_id: str):
        return self._make_request("GET", f"/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}/attachments/{attachment_id}/query-result")

    # API 4
    def send_message(self, space_id: str, conversation_id: str, content: str):
        return self._make_request("POST", f"/spaces/{space_id}/conversations/{conversation_id}/messages", json={"content": content})

    # Bonus APIs
    def list_spaces(self):
        result = self._make_request("GET", "/spaces")
        return result.get("spaces", []) if result else []

    def get_space(self, space_id: str):
        return self._make_request("GET", f"/spaces/{space_id}")
```

#### **2. Data Parsing Function**
```python
def parse_query_result(result_data: Dict) -> Tuple[Optional[pd.DataFrame], int, bool]:
    """
    Parses API #3 response into pandas DataFrame

    Returns:
        - DataFrame with query results
        - total_row_count (for pagination)
        - truncated (boolean)
    """
    statement_response = result_data.get("statement_response", {})
    manifest = statement_response.get("manifest", {})
    result = statement_response.get("result", {})

    # Extract column names from schema
    columns = []
    schema = manifest.get("schema", {})
    if "columns" in schema:
        columns = [col.get("name", f"col_{i}") for i, col in enumerate(schema["columns"])]

    # Extract data rows
    rows = []
    data_array = result.get("data_typed_array", [])
    for row in data_array:
        values = row.get("values", [])
        row_data = []
        for value in values:
            # Extract typed value
            if "str" in value:
                row_data.append(value["str"])
            elif "int" in value:
                row_data.append(value["int"])
            elif "long" in value:
                row_data.append(value["long"])
            elif "double" in value:
                row_data.append(value["double"])
            elif "bool" in value:
                row_data.append(value["bool"])
            else:
                row_data.append(str(value))
        rows.append(row_data)

    # Create DataFrame
    if rows and columns:
        df = pd.DataFrame(rows, columns=columns)
    else:
        df = None

    total_rows = manifest.get("total_row_count", 0)
    truncated = manifest.get("truncated", False)

    return df, total_rows, truncated
```

#### **3. Complete Flow Implementation**
```python
# User asks question
user_query = st.chat_input("Ask Genie a question...")

if user_query:
    # Add to chat history
    st.session_state.chat_history.append({"role": "user", "content": user_query})

    # Step 1: Start/send conversation (API #1 or #4)
    if st.session_state.current_conversation_id:
        # Follow-up
        response = client.send_message(space_id, conversation_id, user_query)
    else:
        # New conversation
        response = client.start_conversation(space_id, user_query)
        st.session_state.current_conversation_id = response.get("conversation_id")

    # Step 2: Get full message details (API #2) - THE CRITICAL STEP!
    message_id = response.get("id") or response.get("message_id")
    message_details = client.get_message(space_id, conversation_id, message_id)

    # Step 3: Extract information
    attachments = message_details.get("attachments", [])
    if attachments:
        attachment = attachments[0]
        query_info = attachment.get("query", {})

        # Store these for later display
        details = {
            "sql": query_info.get("query"),
            "description": query_info.get("description"),
            "statement_id": query_info.get("statement_id"),
            "attachment_id": attachment.get("id")  # CRITICAL: Need this for API #3!
        }

        st.session_state.message_details[message_id] = details

    # Display: SQL and description shown immediately
    # User clicks "Show Query Results" button

    # Step 4: Fetch actual data (API #3) - triggered by button click
    if st.button("📊 Show Query Results"):
        result_data = client.get_query_result(
            space_id,
            conversation_id,
            message_id,
            details["attachment_id"]
        )

        # Step 5: Parse and display
        df, total_rows, truncated = parse_query_result(result_data)

        # Show pagination info
        if total_rows > len(df) or truncated:
            st.info(f"📊 Showing {len(df):,} of {total_rows:,} total rows")

        # Display data table
        st.dataframe(df, use_container_width=True)
```

### **UI Structure**

#### **Tab 1: 🗂️ Spaces**
- Lists all Genie spaces using `list_spaces()` API
- Shows space name, description, ID
- "Select Space" button sets `st.session_state.current_space_id`

#### **Tab 2: 💬 Conversations**
- Shows conversations in selected space (if API available)
- Currently placeholder - list conversations API may not exist

#### **Tab 3: 🧞 Chat**
- Main chat interface
- Shows conversation history
- For each assistant message:
  - Natural language response
  - Query description (ℹ️ info box)
  - SQL code (```sql code block)
  - "📊 Show Query Results" button
- Chat input for questions/follow-ups

---

## 📊 User's Organization-Specific Findings

### **Fields Available in API Responses:**

From debug output user provided:

#### **API #2 (Get Message) Returns:**
```
✅ id: "01f0bf1613dflel7b3ae3b0d9eеa3db4"
✅ conversation_id: "01f0bf16002aldff8c92dal608ea19b5"
✅ status: "COMPLETED"
✅ attachments[0].query.query: SQL string
✅ attachments[0].query.description: "You're looking to calculate..."
✅ attachments[0].query.statement_id: UUID
✅ attachments[0].id: attachment_id
✅ created_timestamp: 1762876199211
✅ last_updated_timestamp: 1762876223811

❌ attachments[0].text.content: False (no natural language response)
❌ attachments[0].query.title: None
❌ attachments[0].suggested_questions: False
❌ attachments[0].query_result_metadata: False (at message level)
```

#### **API #3 (Get Query Result) Expected:**
```
✅ manifest.schema.columns: Array of column definitions
✅ manifest.total_row_count: Number (for pagination)
✅ manifest.truncated: Boolean
✅ result.data_typed_array: Array of row data
```

### **Features NOT Available (Org-Specific):**
- Query titles
- Suggested follow-up questions
- Natural language text responses in attachments
- Query result metadata at message level

### **Workarounds Implemented:**
- Use `.get()` for all dictionary access (prevents KeyError)
- Show "Query processed successfully!" if no text.content
- Pagination info from API #3's manifest, not API #2

---

## 🚀 Current Status

### **Files Created:**
1. **app_v2.py** (~460 lines)
   - Complete implementation with direct REST APIs
   - Three-tab interface
   - All 4 API flows implemented
   - Safe dictionary access with `.get()`

2. **requirements.txt**
   ```
   streamlit==1.31.0
   databricks-sdk==0.23.0
   python-dotenv==1.0.1
   pandas>=2.0.0
   requests>=2.31.0
   ```

3. **V2_MIGRATION_GUIDE.md**
   - Complete problem explanation
   - API flow comparison
   - Usage guide
   - Troubleshooting

4. **POSTMAN_API_COLLECTION.md**
   - All API details
   - Request/response examples
   - Ready-to-import JSON collection

5. **LOGS_LOCATION.md**
   - Logging setup guide
   - For debugging

### **Fixed Issues:**
- ✅ KeyError: 'id' - changed all `dict['key']` to `dict.get('key')`
- ✅ Missing API #2 call - now properly fetches message details
- ✅ Missing attachment_id - now extracted from API #2
- ✅ Data not displaying - now works via API #3

### **Testing Status:**
- ⏳ **Pending:** User needs to test app_v2.py
- ⏳ **Pending:** Verify data matches Bruno testing results
- ⏳ **Pending:** Confirm pagination info shows correctly

---

## 🧪 Next Steps for Testing

### **1. Environment Setup**
```bash
cd /home/user/Genieapi
pip install -r requirements.txt
```

### **2. Run V2 App**
```bash
streamlit run app_v2.py
```

### **3. Test Checklist**

#### **Spaces Tab:**
- [ ] Lists spaces without errors
- [ ] Shows space names and IDs
- [ ] "Select Space" works
- [ ] Selected space shows in sidebar

#### **Chat Tab:**
- [ ] Can type and send questions
- [ ] See query description in info box
- [ ] See SQL in code block
- [ ] "📊 Show Query Results" button appears
- [ ] Button fetches and displays data
- [ ] Data matches Bruno results exactly:
  - Same columns
  - Same data values
  - Same row counts
- [ ] Pagination info shows: "Showing X of Y rows"
- [ ] Follow-up questions maintain context
- [ ] Follow-up data also fetchable

#### **Error Handling:**
- [ ] Invalid queries show error messages
- [ ] HTTP errors display properly
- [ ] Missing fields don't crash app

### **4. Comparison with Bruno**
User should:
1. Ask same query in app_v2.py that they tested in Bruno
2. Click "Show Query Results"
3. Compare:
   - Column names match?
   - Data values match?
   - Row counts match?
   - Pagination info correct?

---

## 🐛 Known Issues & Workarounds

### **Issue 1: No Natural Language Responses**
**Symptom:** User's org doesn't get `attachments[0].text.content`
**Workaround:** App shows "✅ Query processed successfully!" instead
**Code:** Line 430 in app_v2.py

### **Issue 2: No Query Titles**
**Symptom:** `query.title` is always `None`
**Workaround:** Skip title display if None
**Code:** Line 340 checks `if details.get("description")`

### **Issue 3: No Suggested Questions**
**Symptom:** `suggested_questions` field is False/missing
**Workaround:** Feature not implemented (not available in org)

### **Issue 4: Conversations List May Not Exist**
**Symptom:** Conversations tab shows "No conversations found"
**Workaround:** This is expected - use Chat tab to start conversations
**Code:** Line 154 tries list_conversations but returns [] if fails

---

## 💡 Important Implementation Notes

### **1. Always Use .get() for Dictionary Access**
```python
# ❌ Bad - throws KeyError
space_id = space['id']

# ✅ Good - returns None or default
space_id = space.get('id', 'unknown')
```

### **2. API Call Sequence is Critical**
```
Must always be: API #1 → API #2 → API #3
Cannot skip API #2! It has the attachment_id.
```

### **3. Session State Keys**
```python
st.session_state.current_space_id        # Selected space
st.session_state.current_conversation_id # Active conversation
st.session_state.chat_history            # List of messages
st.session_state.message_details         # Dict of message_id → details
st.session_state[f"result_{message_id}"] # Cached query results
```

### **4. Button Key Management**
Each button needs unique key to avoid Streamlit conflicts:
```python
st.button("Show Results", key=f"btn_result_{idx}")
st.button("Select Space", key=f"select_{space_id}")
```

---

## 📞 Contact Points

### **User Environment:**
- Databricks workspace with Genie API access
- Token-based authentication
- `.env` file with `DATABRICKS_HOST` and `DATABRICKS_TOKEN`
- Tested APIs in Bruno - all 4 APIs confirmed working

### **Demo Requirements:**
- 2-day timeline
- Must show: spaces, queries, SQL, actual data
- Follow-up questions with context
- Industry-standard approach (not academic)

---

## 🎯 Success Criteria

✅ **App should:**
1. List multiple Genie spaces
2. Allow space selection
3. Accept natural language queries
4. Display generated SQL
5. Show query descriptions
6. Fetch actual query results on button click
7. Display data in formatted tables
8. Show pagination info ("X of Y rows")
9. Support follow-up questions
10. Maintain conversation context
11. Handle errors gracefully
12. Match Bruno test results exactly

---

## 📚 Reference Materials

### **User's API Testing Results:**
User confirmed these endpoints work in Bruno:
1. `/api/2.0/genie/spaces/{space_id}/start-conversation` ✅
2. `/api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}` ✅
3. `/api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}/attachments/{attachment_id}/query-result` ✅
4. `/api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages` ✅

### **Databricks Documentation:**
- API docs at: https://docs.databricks.com/api/workspace/genie
- Note: We got 403 when trying to fetch docs, so rely on user's testing results

### **Code Repository:**
- Location: `/home/user/Genieapi/`
- Main file: `app_v2.py`
- Branch: `claude/streamlit-app-plan-011CUzd1SnekK2hovocEbinL`

---

## 🚦 Current Task Priority

**IMMEDIATE:**
1. User needs to test `app_v2.py`
2. Verify data matches Bruno results
3. Confirm all 4 tabs/features work
4. Report any errors or missing features

**IF ERRORS OCCUR:**
1. Check sidebar Debug Info for IDs
2. Verify .env credentials
3. Check browser console for JS errors
4. Look for Python stack traces
5. Verify API responses match expected format

**FUTURE ENHANCEMENTS:**
- Export data to CSV
- Query history
- Conversation search
- Query templates
- Better error messages
- Dark mode

---

## 📝 Quick Command Reference

```bash
# Run the app
streamlit run app_v2.py

# Test specific query
# (In Streamlit UI, type in chat input)

# Check credentials
cat .env

# View recent logs (if logging enabled)
tail -f genie_app.log

# Verify syntax
python -m py_compile app_v2.py

# Install dependencies
pip install -r requirements.txt
```

---

## ✅ Verification Checklist for New LLM

Before making changes, verify understanding:
- [ ] I understand the 4-API flow (start → get_message → get_query_result → send_message)
- [ ] I know API #2 is critical and was missing from SDK approach
- [ ] I understand user's org doesn't return query titles or suggested questions
- [ ] I know all dictionary access must use .get() to prevent KeyErrors
- [ ] I understand the three-tab interface design
- [ ] I know the user tested in Bruno and confirmed APIs work
- [ ] I understand data fetching is user-triggered via button click
- [ ] I know pagination info comes from API #3's manifest, not API #2

---

## 🎉 Summary

**What We Built:**
A Streamlit app (`app_v2.py`) that uses direct REST API calls to Databricks Genie, following the exact 4-API flow the user confirmed working in Bruno.

**Why It Should Work:**
1. We're using the exact API endpoints user tested
2. We're making the critical API #2 call the SDK was skipping
3. We're extracting attachment_id correctly
4. We're handling org-specific field availability

**What's Next:**
User needs to run `streamlit run app_v2.py` and verify it matches their Bruno testing results.

---

**END OF HANDOFF DOCUMENT**

*This document contains all context needed to understand the project, continue development, or debug issues.*