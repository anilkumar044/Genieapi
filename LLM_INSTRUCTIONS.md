# STRICT INSTRUCTIONS: Build Streamlit App with Databricks Genie API Integration

## OBJECTIVE
Build a production-ready Streamlit application that integrates with Databricks Genie API to enable natural language querying of data through a conversational interface. This is for a 2-day demo.

---

## CONSTRAINTS & REQUIREMENTS

### MUST HAVE (Critical for Demo)
1. Single-file Streamlit application (`app.py`)
2. Token-based authentication (simplest approach)
3. Chat interface with message history
4. Natural language query input
5. Display responses including:
   - Natural language answers
   - Generated SQL queries
   - Query descriptions
   - Row count metadata
6. Conversation context preservation (follow-up questions work)
7. Error handling with user-friendly messages
8. Environment variable configuration
9. Complete setup documentation

### MUST NOT HAVE (Out of Scope)
1. Complex multi-file architecture
2. Database persistence for conversations
3. User authentication system
4. Advanced data visualizations (charts/graphs)
5. Rate limiting implementation
6. Multi-space switching (single space only for MVP)
7. Query result data fetching (SQL display only, not actual data)

### NICE TO HAVE (If Time Permits)
1. Example query suggestions
2. Syntax highlighting for SQL
3. Copy SQL to clipboard button
4. Space information display
5. New conversation button
6. Clear history button

---

## TECHNICAL SPECIFICATIONS

### Technology Stack
- **Framework**: Streamlit 1.31.0+
- **SDK**: databricks-sdk 0.23.0+
- **Python**: 3.8+
- **Environment**: python-dotenv 1.0.1+

### Databricks Genie API Endpoints to Use

#### PRIMARY ENDPOINTS (REQUIRED)
```python
# Start a new conversation
w.genie.start_conversation_and_wait(
    space_id: str,
    content: str
) -> GenieMessage

# Send follow-up message in existing conversation
w.genie.create_message_and_wait(
    space_id: str,
    conversation_id: str,
    content: str
) -> GenieMessage

# Get space information
w.genie.get_space(space_id: str) -> GenieSpace
```

#### CRITICAL: What These Methods Return

**GenieMessage Response Structure:**
```python
{
    "id": "message_123",
    "conversation_id": "conv_456",
    "status": "COMPLETED",
    "attachments": [
        {
            "text": {
                "content": "Here are your top 10 customers..."
            },
            "query": {
                "query": "SELECT customer_name, SUM(revenue) ...",  # THE SQL
                "description": "Retrieves top customers by revenue"
            },
            "query_result_metadata": {
                "row_count": 10,
                "truncated": false
            }
        }
    ]
}
```

**IMPORTANT**: The `_and_wait()` methods automatically poll the API until completion and return the FULL response including SQL. You do NOT need separate API calls for SQL retrieval!

#### ENDPOINTS TO IGNORE (Not Needed for MVP)
- `list_spaces()` - Multi-space support not needed
- `get_message_attachment_query_result()` - Actual data fetching not needed
- `execute_message_attachment_query()` - Re-execution not needed
- Conversation listing/deletion - Persistence not needed
- Feedback APIs - Not needed for demo

---

## IMPLEMENTATION STEPS

### Step 1: Project Structure
Create the following files:

```
Genieapi/
├── app.py                  # Main application (ONLY Python file needed)
├── requirements.txt        # Dependencies
├── .env.example           # Configuration template
├── .gitignore            # Git ignore rules
├── README.md             # User documentation
└── QUICKSTART.md         # 5-minute setup guide
```

### Step 2: Dependencies (requirements.txt)
```
streamlit==1.31.0
databricks-sdk==0.23.0
python-dotenv==1.0.1
```

### Step 3: Environment Variables (.env.example)
```env
# Databricks Configuration
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=dapiXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Genie Space Configuration
GENIE_SPACE_ID=01XXXXXXXXXXXXXXXXXXXXXXXXXX

# Optional: App Configuration
APP_TITLE=Genie Chat Assistant
APP_ICON=🤖
```

### Step 4: Git Ignore (.gitignore)
```
.env
__pycache__/
*.py[cod]
.venv/
venv/
.streamlit/secrets.toml
*.log
```

### Step 5: Main Application (app.py)

#### 5.1 Required Imports
```python
import os
import streamlit as st
from typing import Optional
from dotenv import load_dotenv
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.dashboards import GenieMessage
```

#### 5.2 Page Configuration
```python
load_dotenv()

st.set_page_config(
    page_title=os.getenv("APP_TITLE", "Genie Chat Assistant"),
    page_icon=os.getenv("APP_ICON", "🤖"),
    layout="wide",
    initial_sidebar_state="expanded"
)
```

#### 5.3 GenieClient Class (REQUIRED)
```python
class GenieClient:
    """Wrapper for Databricks Genie API"""

    def __init__(self, host: str, token: str, space_id: str):
        """Initialize client with credentials"""
        self.space_id = space_id
        try:
            self.client = WorkspaceClient(host=host, token=token)
            # Test connection
            self.client.current_user.me()
        except Exception as e:
            st.error(f"Failed to initialize: {str(e)}")
            st.stop()

    def start_conversation(self, query: str) -> Optional[GenieMessage]:
        """Start new conversation - Returns message with SQL in attachments"""
        try:
            with st.spinner("🧞 Genie is thinking..."):
                response = self.client.genie.start_conversation_and_wait(
                    space_id=self.space_id,
                    content=query
                )
            return response
        except Exception as e:
            st.error(f"Error: {str(e)}")
            return None

    def send_message(self, conversation_id: str, query: str) -> Optional[GenieMessage]:
        """Send follow-up message - Returns message with SQL in attachments"""
        try:
            with st.spinner("🧞 Genie is thinking..."):
                response = self.client.genie.create_message_and_wait(
                    space_id=self.space_id,
                    conversation_id=conversation_id,
                    content=query
                )
            return response
        except Exception as e:
            st.error(f"Error: {str(e)}")
            return None

    def get_space_info(self):
        """Get space information for display"""
        try:
            return self.client.genie.get_space(self.space_id)
        except Exception as e:
            st.warning(f"Could not fetch space info: {str(e)}")
            return None
```

#### 5.4 Session State Initialization (REQUIRED)
```python
def initialize_session_state():
    """Initialize Streamlit session state variables"""
    if 'conversation_id' not in st.session_state:
        st.session_state.conversation_id = None
    if 'messages' not in st.session_state:
        st.session_state.messages = []
    if 'genie_client' not in st.session_state:
        st.session_state.genie_client = None
```

#### 5.5 Response Formatting (CRITICAL)
```python
def format_genie_response(response: GenieMessage) -> str:
    """
    Format Genie response for display

    IMPORTANT: The response.attachments contains:
    - attachment.text.content: Natural language answer
    - attachment.query.query: THE SQL (already included!)
    - attachment.query.description: What the SQL does
    - attachment.query_result_metadata: Row counts, truncation info
    """
    if not response:
        return "No response received from Genie."

    formatted_text = ""

    if response.attachments:
        for attachment in response.attachments:
            # Natural language answer
            if attachment.text and attachment.text.content:
                formatted_text += attachment.text.content + "\n\n"

            # Query information
            if attachment.query:
                # Query description (what the SQL does)
                if hasattr(attachment.query, 'description') and attachment.query.description:
                    formatted_text += f"**Query Description:** {attachment.query.description}\n\n"

                # Generated SQL (IT'S HERE!)
                if attachment.query.query:
                    formatted_text += "**Generated SQL:**\n```sql\n"
                    formatted_text += attachment.query.query + "\n```\n\n"

            # Query result metadata (row counts)
            if hasattr(attachment, 'query_result_metadata') and attachment.query_result_metadata:
                metadata = attachment.query_result_metadata
                if hasattr(metadata, 'row_count') and metadata.row_count is not None:
                    formatted_text += f"📊 **Results:** {metadata.row_count} row(s) returned"
                    if hasattr(metadata, 'truncated') and metadata.truncated:
                        formatted_text += " (truncated)"
                    formatted_text += "\n\n"

    return formatted_text if formatted_text else "Genie processed your query."
```

#### 5.6 Sidebar (OPTIONAL but Recommended)
```python
def display_sidebar():
    """Display sidebar with controls and info"""
    with st.sidebar:
        st.title("⚙️ Configuration")

        # Connection status
        if st.session_state.genie_client:
            st.success("✅ Connected to Databricks")

            # Space info
            space_info = st.session_state.genie_client.get_space_info()
            if space_info:
                st.info(f"**Space:** {space_info.name if hasattr(space_info, 'name') else 'Unknown'}")
        else:
            st.error("❌ Not connected")

        st.divider()

        # Conversation controls
        st.subheader("💬 Conversation")

        if st.session_state.conversation_id:
            st.text("Active conversation")
            if st.button("🔄 New Conversation", use_container_width=True):
                st.session_state.conversation_id = None
                st.session_state.messages = []
                st.rerun()
        else:
            st.text("No active conversation")

        if st.button("🗑️ Clear Chat History", use_container_width=True):
            st.session_state.messages = []
            st.rerun()

        st.divider()

        # Example queries (OPTIONAL)
        st.subheader("💡 Example Queries")
        examples = [
            "Show me the top 10 customers by revenue",
            "What were total sales last month?",
            "Show me trends over the last 6 months",
            "Which products have the highest margins?",
        ]

        for example in examples:
            if st.button(f"📝 {example}", key=example, use_container_width=True):
                return example

        st.divider()

        # About
        with st.expander("ℹ️ About"):
            st.markdown("""
            **Genie Chat Assistant**

            Ask questions about your data in natural language.

            **Tips:**
            - Be specific with your questions
            - Use example queries for inspiration
            - Start a new conversation for different topics
            """)

    return None
```

#### 5.7 Main Function (REQUIRED)
```python
def main():
    """Main application entry point"""

    # Initialize session state
    initialize_session_state()

    # App header
    st.title("🧞 Databricks Genie Chat Assistant")
    st.markdown("*Ask questions about your data in natural language*")

    # Check for required environment variables
    host = os.getenv("DATABRICKS_HOST")
    token = os.getenv("DATABRICKS_TOKEN")
    space_id = os.getenv("GENIE_SPACE_ID")

    if not all([host, token, space_id]):
        st.error("""
        ⚠️ **Configuration Missing**

        Please set up your `.env` file with:
        - `DATABRICKS_HOST`
        - `DATABRICKS_TOKEN`
        - `GENIE_SPACE_ID`

        See `.env.example` for reference.
        """)
        st.stop()

    # Initialize Genie client (only once)
    if st.session_state.genie_client is None:
        st.session_state.genie_client = GenieClient(host, token, space_id)

    # Display sidebar (returns example query if clicked)
    example_query = display_sidebar()

    # Display chat history
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])

    # Chat input
    user_query = st.chat_input("Ask me anything about your data...")

    # Use example query if clicked
    if example_query:
        user_query = example_query

    # Process user input
    if user_query:
        # Add user message to chat
        st.session_state.messages.append({"role": "user", "content": user_query})
        with st.chat_message("user"):
            st.markdown(user_query)

        # Get response from Genie
        genie_client = st.session_state.genie_client

        if st.session_state.conversation_id is None:
            # Start new conversation
            response = genie_client.start_conversation(user_query)
            if response:
                st.session_state.conversation_id = response.conversation_id
        else:
            # Continue existing conversation
            response = genie_client.send_message(
                st.session_state.conversation_id,
                user_query
            )

        # Display response
        if response:
            formatted_response = format_genie_response(response)
            st.session_state.messages.append({
                "role": "assistant",
                "content": formatted_response
            })
            with st.chat_message("assistant"):
                st.markdown(formatted_response)
        else:
            error_msg = "❌ Failed to get response from Genie. Please try again."
            st.session_state.messages.append({
                "role": "assistant",
                "content": error_msg
            })
            with st.chat_message("assistant"):
                st.error(error_msg)

    # Footer
    st.divider()
    st.caption("Powered by Databricks Genie API | Built with Streamlit")


if __name__ == "__main__":
    main()
```

---

## CONFIGURATION REQUIREMENTS

### User Must Provide (in .env file)
1. **DATABRICKS_HOST**: Full workspace URL (e.g., `https://dbc-abc123.cloud.databricks.com`)
2. **DATABRICKS_TOKEN**: Personal access token from Databricks
   - Generated from: User Settings → Developer → Access tokens
3. **GENIE_SPACE_ID**: Space ID from Genie space URL
   - Found in URL: `.../genie/rooms/01abc123...`

### How to Get Credentials
**Step 1: Databricks Host**
- Look at browser URL when logged into Databricks workspace

**Step 2: Personal Access Token**
1. In Databricks: Click profile → User Settings
2. Navigate to: Developer → Access tokens
3. Click "Generate new token"
4. Copy immediately (shown only once!)

**Step 3: Genie Space ID**
1. Open Genie Space in Databricks
2. Look at URL: `.../genie/rooms/<SPACE_ID>`
3. Copy the SPACE_ID portion

---

## TESTING CHECKLIST

### Before Demo
- [ ] App starts without errors: `streamlit run app.py`
- [ ] Browser opens to `http://localhost:8501`
- [ ] Connection status shows "✅ Connected to Databricks"
- [ ] Space name displays correctly in sidebar
- [ ] Can submit a test query (e.g., "Show me sample data")
- [ ] Response appears with:
  - [ ] Natural language answer
  - [ ] SQL query in code block
  - [ ] Row count (if available)
- [ ] Can ask follow-up question (conversation context works)
- [ ] "New Conversation" button works
- [ ] "Clear Chat History" button works
- [ ] Example queries work when clicked
- [ ] No Python errors in terminal
- [ ] No errors shown in browser

### Test Queries (Use with Your Data)
1. "Show me sample data from [your_table]"
2. "Count rows in [your_table]"
3. "Show me top 10 [entities] by [metric]"
4. Follow-up: "What about last month?" (tests context)

---

## ERROR HANDLING REQUIREMENTS

### MUST Handle
1. **Missing environment variables**
   - Show clear error message
   - Stop execution with `st.stop()`
   - Tell user which variables are missing

2. **Authentication failures**
   - Catch exception in `__init__`
   - Show error message
   - Stop execution

3. **API errors**
   - Catch in each API method
   - Show user-friendly error in UI
   - Log to console for debugging
   - Return None (don't crash)

4. **Missing response data**
   - Check if response is None
   - Check if attachments exist
   - Use hasattr() for optional fields
   - Graceful fallback messages

### Example Error Handling Pattern
```python
try:
    response = self.client.genie.start_conversation_and_wait(...)
    return response
except Exception as e:
    st.error(f"Error starting conversation: {str(e)}")
    return None
```

---

## DOCUMENTATION REQUIREMENTS

### README.md Must Include
1. Quick start guide (5 minutes to running)
2. How to get Databricks credentials
3. Installation steps
4. Configuration instructions
5. How to run the app
6. Troubleshooting common issues
7. Example queries

### QUICKSTART.md Must Include
1. Step-by-step setup (numbered)
2. Exact commands to run
3. Where to find credentials
4. How to test setup
5. Demo script (what to say/show)
6. Emergency troubleshooting

---

## SUCCESS CRITERIA

### Minimum Viable Product (Must Have)
- [ ] App runs without errors
- [ ] User can ask questions in natural language
- [ ] Responses show natural language answers
- [ ] Responses show generated SQL queries
- [ ] Follow-up questions maintain context
- [ ] Errors are handled gracefully
- [ ] Configuration is clear and documented
- [ ] Setup takes < 15 minutes

### Demo Ready (Should Have)
- [ ] Professional UI (clean, not cluttered)
- [ ] Loading indicators during processing
- [ ] Clear status messages
- [ ] Example queries available
- [ ] Conversation management (new/clear)
- [ ] Space information displayed

### Nice to Have (Optional)
- [ ] SQL syntax highlighting
- [ ] Copy SQL button
- [ ] Query descriptions shown
- [ ] Row count metadata displayed
- [ ] Responsive design

---

## COMMON PITFALLS TO AVOID

### ❌ DO NOT
1. **Try to fetch actual data rows** - Not needed for MVP, only SQL
2. **Implement manual polling** - `_and_wait()` methods handle it
3. **Create complex multi-file architecture** - Single file is fine
4. **Add database persistence** - Session state is sufficient
5. **Implement rate limiting** - Not needed for single-user demo
6. **Add user authentication** - Token auth is enough
7. **Create separate APIs for SQL** - It's in the response!
8. **Over-engineer** - Simple is better for demo

### ✅ DO
1. **Use `_and_wait()` methods** - They handle polling automatically
2. **Check for None/missing data** - Use hasattr() and if checks
3. **Show SQL in responses** - It's in `attachment.query.query`
4. **Handle errors gracefully** - User-friendly messages
5. **Keep it simple** - Single file, clear logic
6. **Test with real data** - Use actual Genie space
7. **Document clearly** - README for setup
8. **Follow the example code** - Don't deviate unless necessary

---

## DEPLOYMENT (Optional)

### Local Development (Primary)
```bash
streamlit run app.py
```
Access at: `http://localhost:8501`

### Docker (If Needed)
```dockerfile
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
```

---

## TIMELINE EXPECTATIONS

### Day 1 (4-6 hours)
- Hour 1-2: Setup environment, install dependencies
- Hour 2-3: Implement GenieClient class
- Hour 3-4: Build main UI and chat interface
- Hour 4-5: Add response formatting
- Hour 5-6: Testing and bug fixes

### Day 2 (2-4 hours)
- Hour 1-2: Polish UI, add sidebar features
- Hour 2-3: Write documentation
- Hour 3-4: Final testing and demo prep

---

## QUALITY STANDARDS

### Code Quality
- [ ] No hardcoded credentials
- [ ] All sensitive data in environment variables
- [ ] Proper error handling (try/except)
- [ ] Clear function names and docstrings
- [ ] Type hints where appropriate
- [ ] No unused imports or code

### UI/UX Quality
- [ ] Clean, uncluttered interface
- [ ] Loading indicators for async operations
- [ ] Clear error messages
- [ ] Responsive to user actions
- [ ] Professional appearance

### Documentation Quality
- [ ] Clear, step-by-step instructions
- [ ] No assumptions about user knowledge
- [ ] All commands are copy-pasteable
- [ ] Screenshots or examples where helpful
- [ ] Troubleshooting section included

---

## FINAL CHECKLIST

Before delivering to user:
- [ ] All Python files have no syntax errors
- [ ] `requirements.txt` has correct versions
- [ ] `.env.example` has all required variables
- [ ] `.gitignore` prevents credential leaks
- [ ] README.md is complete and clear
- [ ] QUICKSTART.md has step-by-step setup
- [ ] App runs successfully: `streamlit run app.py`
- [ ] Can connect to Databricks
- [ ] Can send queries and get responses
- [ ] SQL displays correctly
- [ ] Follow-up questions work
- [ ] Example queries work
- [ ] Error handling works
- [ ] No crashes or exceptions

---

## SUPPORT RESOURCES

### Official Documentation
- Databricks Genie API: https://docs.databricks.com/api/workspace/genie
- Databricks Python SDK: https://databricks-sdk-py.readthedocs.io/
- Streamlit Docs: https://docs.streamlit.io/

### Key Code References
- GenieMessage structure: See `format_genie_response()` function above
- API methods: See `GenieClient` class above
- Session state: See `initialize_session_state()` function above

---

## EXPECTED OUTPUT

When working correctly, a user query like "Show me top 10 customers" should produce output like:

```
Here are your top 10 customers by revenue:

**Query Description:** Retrieves the top 10 customers ranked by total revenue

**Generated SQL:**
```sql
SELECT
    customer_name,
    SUM(revenue) as total_revenue
FROM sales
GROUP BY customer_name
ORDER BY total_revenue DESC
LIMIT 10
```

📊 **Results:** 10 row(s) returned
```

---

## END OF INSTRUCTIONS

Follow these instructions strictly. Do not add features not listed. Do not skip error handling. Do not deviate from the structure unless absolutely necessary. The goal is a working demo in 2 days, not a perfect production system.

**Priority**: Working > Perfect
**Scope**: MVP > Feature-rich
**Timeline**: 2 days > Optimal architecture
