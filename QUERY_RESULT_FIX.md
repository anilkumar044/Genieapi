# Query Result Data Display - Fix Documentation

## 🐛 The Problem You Encountered

**What you saw:**
- ✅ SQL query displayed
- ✅ Query description displayed
- ✅ Row count shown
- ❌ **No actual data rows** (customer names, revenue values, etc.)

**What you expected:**
- The actual result data like you see in Databricks UI Genie conversation history

## 🔍 Root Cause Analysis

### Why This Happened

The Genie API has **two separate operations**:

1. **Get the answer and SQL** (what we were doing)
   ```python
   response = w.genie.start_conversation_and_wait(...)
   # Returns: Natural language answer, SQL query, metadata
   # Does NOT return: Actual data rows
   ```

2. **Get the actual data** (what we were missing)
   ```python
   result = w.genie.get_message_query_result(
       space_id, conversation_id, message_id, attachment_id
   )
   # Returns: The actual data rows, schema, etc.
   ```

### Why Databricks UI Shows Data

When you use Genie in the Databricks UI:
1. UI sends your question to Genie API
2. UI receives response with SQL
3. **UI automatically makes a second API call** to fetch data
4. UI displays everything together

Our app was only doing step 1-2, not step 3!

---

## ✅ The Solution Implemented

### What I Added

#### 1. New Method: `get_query_result()`
```python
def get_query_result(self, conversation_id: str, message_id: str, attachment_id: str):
    """Fetch actual query result data (the rows)"""
    result = self.client.genie.get_message_query_result(
        space_id=self.space_id,
        conversation_id=conversation_id,
        message_id=message_id,
        attachment_id=attachment_id
    )
    return result
```

**What it does:** Makes the second API call to fetch actual data rows.

#### 2. New Function: `display_query_results()`
```python
def display_query_results(genie_client, response: GenieMessage):
    """Fetch and display actual query result data as tables"""
    # For each attachment with a query:
    # 1. Extract attachment_id
    # 2. Fetch the actual data
    # 3. Parse the data structure
    # 4. Convert to pandas DataFrame
    # 5. Display as a nice table
```

**What it does:**
- Fetches data for each query in the response
- Parses the complex data structure
- Converts to readable table format
- Displays with `st.dataframe()`

#### 3. Updated Main Flow
```python
# Display response
if response:
    # Step 1: Show text and SQL
    st.markdown(formatted_response)

    # Step 2: Fetch and show actual data (NEW!)
    display_query_results(genie_client, response)
```

---

## 📊 Understanding the Data Structure

### What `get_message_query_result()` Returns

```python
{
  "statement_response": {
    "manifest": {
      "schema": {
        "columns": [
          {"name": "warehouse_id", "type_name": "STRING"},
          {"name": "total_dbu", "type_name": "DECIMAL"},
          {"name": "usage_date", "type_name": "DATE"}
        ]
      },
      "total_row_count": 42
    },
    "result": {
      "data_typed_array": [
        {
          "values": [
            {"str": "fdobd245c1326082"},
            {"str": "150.75"},
            {"str": "2025-10-01"}
          ]
        },
        {
          "values": [
            {"str": "fd0bd245c1326082"},
            {"str": "200.50"},
            {"str": "2025-10-02"}
          ]
        }
        // ... more rows
      ]
    }
  }
}
```

### How We Parse It

1. **Extract schema** → Get column names
2. **Extract data_typed_array** → Get rows
3. **For each row's values** → Extract typed data:
   - `value.str` for strings
   - `value.int` for integers
   - `value.long` for big integers
   - `value.double` for decimals
   - `value.bool` for booleans
4. **Create DataFrame** → `pd.DataFrame(rows, columns=columns)`
5. **Display** → `st.dataframe(df)`

---

## 🎨 What You'll See Now

### Before (Old Behavior)
```
Here are your SQL Warehouse costs...

Query Description: Calculates usage costs for specified warehouses

Generated SQL:
```sql
SELECT warehouse_id, SUM(usage_quantity) as total_dbu
FROM system.billing.usage
WHERE ...
```

📊 Results: 42 row(s) returned
```

**That's it. No actual data!**

### After (New Behavior)
```
Here are your SQL Warehouse costs...

Query Description: Calculates usage costs for specified warehouses

Generated SQL:
```sql
SELECT warehouse_id, SUM(usage_quantity) as total_dbu
FROM system.billing.usage
WHERE ...
```

📊 Results: 42 row(s) returned

[INTERACTIVE TABLE SHOWING:]
| warehouse_id        | total_dbu | usage_date |
|--------------------|-----------|------------|
| fdobd245c1326082   | 150.75    | 2025-10-01 |
| fd0bd245c1326082   | 200.50    | 2025-10-02 |
| c3a511209eb506c9   | 175.25    | 2025-10-03 |
| ...                | ...       | ...        |
```

**Now you see the actual data!**

---

## 🔧 Technical Details

### API Call Sequence

**Your Query: "Show me SQL Warehouse costs"**

```
1. POST /api/2.0/genie/spaces/{space_id}/start-conversation
   Request: { "content": "Show me SQL Warehouse costs" }
   Response: {
     "id": "msg_123",
     "conversation_id": "conv_456",
     "attachments": [{
       "id": "attach_789",  ← Important!
       "text": { "content": "Here are your costs..." },
       "query": { "query": "SELECT ..." }
     }]
   }

2. GET /api/2.0/genie/spaces/{space_id}/conversations/{conv_456}/messages/{msg_123}/query-result/{attach_789}
   Request: (none, just the URL)
   Response: {
     "statement_response": {
       "manifest": { ... schema ... },
       "result": { "data_typed_array": [ ... rows ... ] }
     }
   }
```

### Error Handling

The code handles several error scenarios:

1. **No result data**
   ```python
   st.info("Query executed successfully but returned no data to display.")
   ```

2. **Missing pandas**
   ```python
   st.warning("pandas not installed. Install with: pip install pandas")
   ```

3. **Data parsing errors**
   ```python
   st.warning(f"Could not display data table: {str(e)}")
   # Shows raw data in expander for debugging
   ```

4. **API call failure**
   ```python
   st.warning(f"Could not fetch query results: {str(e)}")
   # Silently fails, doesn't crash the app
   ```

---

## 📦 Dependencies Added

```diff
streamlit==1.31.0
databricks-sdk==0.23.0
python-dotenv==1.0.1
+ pandas>=2.0.0
```

**Why pandas?**
- Streamlit's `st.dataframe()` works best with pandas DataFrames
- Makes it easy to display tabular data
- Provides sorting, filtering in the UI automatically

---

## 🚀 How to Use

### Installation
```bash
# Update dependencies
pip install -r requirements.txt
```

### Running
```bash
# Just run as normal
streamlit run app.py
```

### Testing
```bash
# Ask a query that returns data
"Show me SQL Warehouse costs for warehouse_id in ('abc123') and usage_date between '2025-10-01' and '2025-11-10'"

# You should now see:
# 1. Natural language answer
# 2. SQL query
# 3. ACTUAL DATA TABLE ✨
```

---

## 🎯 Behavior Notes

### Data Display
- **New queries**: Show data table immediately
- **Chat history**: Only shows text/SQL (data not stored in history)
- **Large results**: Streamlit automatically adds scrolling
- **Column types**: Properly handled (strings, numbers, dates, booleans)

### Performance
- **First API call**: ~10-60 seconds (Genie thinking)
- **Second API call**: ~1-5 seconds (data retrieval)
- **Total**: Adds a few seconds to response time
- **Worth it**: Now you see actual data!

### Limitations
- **History replay**: Scrolling up only shows text/SQL, not data
- **Large datasets**: May be slow for 10,000+ rows
- **Complex types**: JSON/Arrays shown as strings
- **Truncation**: Respects Genie's row limits

---

## 🐛 Troubleshooting

### "Could not fetch query results"
**Cause**: API call to get_message_query_result() failed

**Solutions:**
1. Check if query actually executed (look for row count)
2. Verify attachment_id exists in response
3. Check Databricks permissions
4. Look at raw error message

### "pandas not installed"
**Cause**: pandas dependency missing

**Solution:**
```bash
pip install pandas>=2.0.0
```

### "Query executed successfully but returned no data"
**Cause**: Query ran but returned 0 rows

**This is normal!** Query might be:
- Filtering too strictly
- Looking at wrong date range
- Targeting empty tables

### Table shows strange values
**Cause**: Unexpected data type in response

**Workaround:**
- Look at "View raw result data" expander
- Check column types in schema
- Report issue with example

---

## 📚 Related Documentation

- **GENIE_API_REFERENCE.md** → Section "Workflow 2: Getting Actual Data"
- **Databricks API Docs** → `get_message_query_result()` endpoint
- **Python SDK Docs** → `w.genie.get_message_query_result()`

---

## ✅ Summary

### What Changed
- ✅ Added `get_query_result()` method
- ✅ Added `display_query_results()` function
- ✅ Updated main flow to fetch and show data
- ✅ Added pandas dependency
- ✅ Added comprehensive error handling

### What You Get Now
- ✅ Natural language answer
- ✅ Query description
- ✅ SQL query
- ✅ Row count
- ✅ **ACTUAL DATA TABLE** ← NEW!

### Next Steps
1. Update your local environment: `pip install -r requirements.txt`
2. Restart Streamlit: `streamlit run app.py`
3. Test with your SQL Warehouse query
4. Verify you see the data table
5. Ready for demo! 🎉

---

**You can now see the complete picture, just like in Databricks UI!**
