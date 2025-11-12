# 🚀 Databricks Genie API - Postman Collection

Complete reference for all APIs used in the Streamlit app. Test each one individually in Postman.

---

## 🔐 Authentication Setup

**For ALL requests, add these headers:**

```
Authorization: Bearer YOUR_DATABRICKS_TOKEN
Content-Type: application/json
```

**Environment Variables to Set:**
- `DATABRICKS_HOST`: `https://your-workspace.cloud.databricks.com`
- `DATABRICKS_TOKEN`: `dapiXXXXXXXXXXXXXXXXXXXXX`
- `SPACE_ID`: `01XXXXXXXXXXXXXXXXXXXXXXXXXX`

---

## 📋 APIs Used in the App

### **1. Start Conversation (Initial Query)**

**What it does:** Ask the first question to Genie, starts a new conversation

**Method:** `POST`

**Endpoint:**
```
{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}/start-conversation
```

**Headers:**
```
Authorization: Bearer {{DATABRICKS_TOKEN}}
Content-Type: application/json
```

**Request Body:**
```json
{
  "content": "Calculate SQL Warehouse usage costs for warehouse_id in ('abc123', 'def456') between 2025-10-01 and 2025-11-10"
}
```

**Example Response:**
```json
{
  "id": "01f0bf1613dflel7b3ae3b0d9eea3db4",
  "conversation_id": "01f0bf16002aldff8c92dal608ea19b5",
  "status": "COMPLETED",
  "created_timestamp": 1762876199211,
  "last_updated_timestamp": 1762876223811,
  "user_id": "8991027584270509",
  "error": null,
  "feedback": null,
  "attachments": [
    {
      "id": "attachment_123",
      "text": {
        "content": "Here's the query to calculate costs..."
      },
      "query": {
        "query": "SELECT warehouse_id, SUM(usage_quantity) as total_usage...",
        "description": "You're looking to calculate the total usage cost...",
        "title": null,
        "statement_id": "01f0bf16-18a4-17c4-8eb8-e8b4617cd6fd"
      },
      "suggested_questions": null,
      "query_result_metadata": null
    }
  ]
}
```

**Key Fields to Check:**
- ✅ `conversation_id` - Save this for follow-up messages
- ✅ `attachments[0].query.query` - The generated SQL
- ✅ `attachments[0].query.description` - Query explanation
- ❓ `attachments[0].query.title` - May be null
- ❓ `attachments[0].suggested_questions` - May be null/missing
- ✅ `attachments[0].id` - Need this to fetch results

---

### **2. Send Message (Follow-up Query)**

**What it does:** Ask follow-up questions in an existing conversation (maintains context)

**Method:** `POST`

**Endpoint:**
```
{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}/conversations/{{CONVERSATION_ID}}/messages
```

**Headers:**
```
Authorization: Bearer {{DATABRICKS_TOKEN}}
Content-Type: application/json
```

**Request Body:**
```json
{
  "content": "Show me only the top 5 results"
}
```

**Example Response:**
```json
{
  "id": "01f0bf17xyz...",
  "conversation_id": "01f0bf16002aldff8c92dal608ea19b5",
  "status": "COMPLETED",
  "created_timestamp": 1762876299211,
  "last_updated_timestamp": 1762876323811,
  "attachments": [
    {
      "id": "attachment_456",
      "query": {
        "query": "SELECT warehouse_id, SUM(usage_quantity) as total_usage... LIMIT 5",
        "description": "Limiting to top 5 warehouses...",
        "statement_id": "01f0bf17-new-statement-id"
      }
    }
  ]
}
```

**When to use:**
- ✅ Follow-up questions
- ✅ Refinements to previous query
- ✅ Maintaining conversation context

---

### **3. Get Message Query Result (Fetch Data Rows)**

**What it does:** Fetch the actual data rows (not just SQL) for a query

**Method:** `GET`

**Endpoint:**
```
{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}/conversations/{{CONVERSATION_ID}}/messages/{{MESSAGE_ID}}/query-result?attachment_id={{ATTACHMENT_ID}}
```

**Headers:**
```
Authorization: Bearer {{DATABRICKS_TOKEN}}
```

**Query Parameters:**
- `attachment_id` (required) - From the message response

**Example URL:**
```
https://your-workspace.cloud.databricks.com/api/2.0/genie/spaces/01ABC.../conversations/01XYZ.../messages/01MSG.../query-result?attachment_id=attachment_123
```

**Example Response:**
```json
{
  "statement_response": {
    "status": {
      "state": "SUCCEEDED"
    },
    "manifest": {
      "schema": {
        "columns": [
          {
            "name": "warehouse_id",
            "type_name": "STRING"
          },
          {
            "name": "total_usage",
            "type_name": "DECIMAL"
          },
          {
            "name": "total_cost",
            "type_name": "DECIMAL"
          }
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

**Key Fields to Check:**
- ✅ `statement_response.manifest.schema.columns` - Column names and types
- ✅ `statement_response.manifest.total_row_count` - Total rows available
- ✅ `statement_response.manifest.truncated` - Whether results are truncated
- ✅ `statement_response.result.data_typed_array` - The actual data rows
- ✅ Each value has a type: `str`, `int`, `long`, `double`, `bool`

**💡 This is where pagination info comes from!**

---

### **4. Get Space Information**

**What it does:** Get details about the Genie Space (name, description, etc.)

**Method:** `GET`

**Endpoint:**
```
{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}
```

**Headers:**
```
Authorization: Bearer {{DATABRICKS_TOKEN}}
```

**Example Response:**
```json
{
  "id": "01ABC...",
  "name": "Sales Analytics",
  "description": "Genie space for sales data analysis",
  "created_timestamp": 1700000000000,
  "updated_timestamp": 1762876199211
}
```

---

### **5. List Spaces**

**What it does:** Get all available Genie Spaces in the workspace

**Method:** `GET`

**Endpoint:**
```
{{DATABRICKS_HOST}}/api/2.0/genie/spaces
```

**Headers:**
```
Authorization: Bearer {{DATABRICKS_TOKEN}}
```

**Example Response:**
```json
{
  "spaces": [
    {
      "id": "01ABC...",
      "name": "Sales Analytics"
    },
    {
      "id": "01DEF...",
      "name": "Marketing Insights"
    }
  ]
}
```

---

## 🧪 Testing Workflow in Postman

### **Test 1: Complete Query Flow**

1. **Get Space Info** (API #4) - Verify space exists
2. **Start Conversation** (API #1) - Ask initial question
   - Note the `conversation_id` from response
   - Note the `message_id` (response.id)
   - Note the `attachment_id` from attachments[0].id
3. **Get Query Result** (API #3) - Fetch actual data
   - Use conversation_id, message_id, attachment_id from step 2
   - Check for pagination info in manifest
4. **Send Follow-up** (API #2) - Ask refinement question
   - Use same conversation_id from step 2

### **Test 2: Field Availability Check**

In each API response, check for:
- ✅ `query.title` - Present or null?
- ✅ `query.description` - Present or null?
- ✅ `suggested_questions` - Present or null?
- ✅ `text.content` - Natural language response
- ✅ `manifest.total_row_count` - In query result API
- ✅ `manifest.truncated` - In query result API

---

## 📝 Postman Collection JSON

Here's a ready-to-import Postman collection:

```json
{
  "info": {
    "name": "Databricks Genie API",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "variable": [
    {
      "key": "DATABRICKS_HOST",
      "value": "https://your-workspace.cloud.databricks.com",
      "type": "string"
    },
    {
      "key": "DATABRICKS_TOKEN",
      "value": "dapiXXXXXXXXXXXXXX",
      "type": "string"
    },
    {
      "key": "SPACE_ID",
      "value": "01XXXXXXXXXX",
      "type": "string"
    },
    {
      "key": "CONVERSATION_ID",
      "value": "",
      "type": "string"
    },
    {
      "key": "MESSAGE_ID",
      "value": "",
      "type": "string"
    },
    {
      "key": "ATTACHMENT_ID",
      "value": "",
      "type": "string"
    }
  ],
  "item": [
    {
      "name": "1. Get Space Info",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{DATABRICKS_TOKEN}}"
          }
        ],
        "url": {
          "raw": "{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}",
          "host": ["{{DATABRICKS_HOST}}"],
          "path": ["api", "2.0", "genie", "spaces", "{{SPACE_ID}}"]
        }
      }
    },
    {
      "name": "2. Start Conversation",
      "request": {
        "method": "POST",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{DATABRICKS_TOKEN}}"
          },
          {
            "key": "Content-Type",
            "value": "application/json"
          }
        ],
        "body": {
          "mode": "raw",
          "raw": "{\n  \"content\": \"Calculate SQL Warehouse usage costs for warehouse_id in ('abc123', 'def456') between 2025-10-01 and 2025-11-10\"\n}"
        },
        "url": {
          "raw": "{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}/start-conversation",
          "host": ["{{DATABRICKS_HOST}}"],
          "path": ["api", "2.0", "genie", "spaces", "{{SPACE_ID}}", "start-conversation"]
        }
      }
    },
    {
      "name": "3. Get Query Result",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{DATABRICKS_TOKEN}}"
          }
        ],
        "url": {
          "raw": "{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}/conversations/{{CONVERSATION_ID}}/messages/{{MESSAGE_ID}}/query-result?attachment_id={{ATTACHMENT_ID}}",
          "host": ["{{DATABRICKS_HOST}}"],
          "path": ["api", "2.0", "genie", "spaces", "{{SPACE_ID}}", "conversations", "{{CONVERSATION_ID}}", "messages", "{{MESSAGE_ID}}", "query-result"],
          "query": [
            {
              "key": "attachment_id",
              "value": "{{ATTACHMENT_ID}}"
            }
          ]
        }
      }
    },
    {
      "name": "4. Send Follow-up Message",
      "request": {
        "method": "POST",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{DATABRICKS_TOKEN}}"
          },
          {
            "key": "Content-Type",
            "value": "application/json"
          }
        ],
        "body": {
          "mode": "raw",
          "raw": "{\n  \"content\": \"Show me only the top 5 results\"\n}"
        },
        "url": {
          "raw": "{{DATABRICKS_HOST}}/api/2.0/genie/spaces/{{SPACE_ID}}/conversations/{{CONVERSATION_ID}}/messages",
          "host": ["{{DATABRICKS_HOST}}"],
          "path": ["api", "2.0", "genie", "spaces", "{{SPACE_ID}}", "conversations", "{{CONVERSATION_ID}}", "messages"]
        }
      }
    },
    {
      "name": "5. List All Spaces",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{DATABRICKS_TOKEN}}"
          }
        ],
        "url": {
          "raw": "{{DATABRICKS_HOST}}/api/2.0/genie/spaces",
          "host": ["{{DATABRICKS_HOST}}"],
          "path": ["api", "2.0", "genie", "spaces"]
        }
      }
    }
  ]
}
```

---

## 🎯 What to Test and Check

### **For Start Conversation API:**
1. Is `attachments[0].text.content` populated? (Natural language response)
2. Is `attachments[0].query.title` null or has value?
3. Is `attachments[0].query.description` populated?
4. Is `attachments[0].suggested_questions` present?
5. Note the `attachment_id` for next step

### **For Get Query Result API:**
1. Does `manifest.total_row_count` exist?
2. Does `manifest.truncated` exist?
3. How many rows in `data_typed_array`?
4. Are column names in `manifest.schema.columns`?

### **For Send Message API:**
1. Same checks as Start Conversation
2. Does it maintain context from previous query?

---

## 📊 Expected Results Based on Your Debug Output

Based on what you shared earlier, you should see in Postman:

| Field | API 1 (Start) | API 2 (Message) | API 3 (Query Result) |
|-------|---------------|-----------------|----------------------|
| `query.title` | `null` ❌ | `null` ❌ | N/A |
| `query.description` | ✅ Has value | ✅ Has value | N/A |
| `suggested_questions` | `null` ❌ | `null` ❌ | N/A |
| `text.content` | ❓ Check | ❓ Check | N/A |
| `manifest.total_row_count` | N/A | N/A | ✅ Should exist |
| `manifest.truncated` | N/A | N/A | ✅ Should exist |

---

## 🔧 Troubleshooting

### **401 Unauthorized**
- Check token is valid: `curl -H "Authorization: Bearer $TOKEN" {{DATABRICKS_HOST}}/api/2.0/clusters/list`
- Verify token hasn't expired

### **404 Not Found - Space ID**
- Run "List All Spaces" first
- Verify SPACE_ID is correct format: `01` followed by 26 characters

### **Empty Response / No Attachments**
- Query might be invalid
- Try simpler query: "Show me sample data from system.usage"

### **Data Fields Missing in Response**
- This is expected based on your org configuration
- Document which fields are consistently null/missing

---

## 💡 Pro Tips

1. **Save Response Values**: After API #2 (Start Conversation), manually copy these to collection variables:
   - `CONVERSATION_ID` from response
   - `MESSAGE_ID` from response.id
   - `ATTACHMENT_ID` from response.attachments[0].id

2. **Use Postman Tests**: Add this script to "Start Conversation" request:
   ```javascript
   pm.test("Response has conversation_id", function() {
       var json = pm.response.json();
       pm.expect(json.conversation_id).to.exist;
       pm.collectionVariables.set("CONVERSATION_ID", json.conversation_id);
       pm.collectionVariables.set("MESSAGE_ID", json.id);
       if (json.attachments && json.attachments.length > 0) {
           pm.collectionVariables.set("ATTACHMENT_ID", json.attachments[0].id);
       }
   });
   ```

3. **Compare with Databricks UI**: After making API calls in Postman, check the same conversation in Databricks Genie UI to compare what fields are shown there vs what you get in API.

---

## 📥 Import to Postman

1. Copy the JSON collection above
2. In Postman: Import → Raw text → Paste JSON → Import
3. Set environment variables in Collection Variables
4. Run requests in order: 5 → 2 → 3

---

## 🚀 Next Steps After Testing

Once you test in Postman:
1. Share which fields are consistently `null` or missing
2. Note any differences between API responses vs Databricks UI
3. Check if pagination info appears in API #3 (Query Result)
4. We can update the app to handle your specific API behavior

This will give you complete visibility into what your Databricks Genie API returns! 🎯
