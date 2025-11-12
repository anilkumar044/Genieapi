"""
Databricks Genie Chat - V2 with Direct REST API Calls
Uses requests library instead of databricks-sdk for full API control
"""

import os
import time
import requests
import pandas as pd
from typing import Optional, Dict, List, Any
from dotenv import load_dotenv
import streamlit as st

# Load environment variables
load_dotenv(override=True)

# Page configuration
st.set_page_config(
    page_title="Genie Chat - Full API",
    page_icon="🧞",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS
st.markdown("""
<style>
    .stTabs [data-baseweb="tab-list"] {
        gap: 24px;
    }
    .stTabs [data-baseweb="tab"] {
        padding: 10px 20px;
    }
    .conversation-item {
        padding: 10px;
        border: 1px solid #ddd;
        border-radius: 5px;
        margin: 5px 0;
        cursor: pointer;
    }
    .conversation-item:hover {
        background-color: #f0f0f0;
    }
</style>
""", unsafe_allow_html=True)


class GenieAPIClient:
    """Direct REST API client for Databricks Genie"""

    def __init__(self, host: str, token: str):
        """Initialize the Genie API client"""
        self.host = host.rstrip('/')
        self.token = token
        self.base_url = f"{self.host}/api/2.0/genie"
        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }

    def _make_request(self, method: str, endpoint: str, **kwargs) -> Optional[Dict]:
        """Make HTTP request to Genie API"""
        url = f"{self.base_url}{endpoint}"
        try:
            response = requests.request(method, url, headers=self.headers, **kwargs)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            st.error(f"HTTP Error: {e.response.status_code} - {e.response.text}")
            return None
        except Exception as e:
            st.error(f"Request failed: {str(e)}")
            return None

    # ========== SPACES API ==========

    def list_spaces(self) -> List[Dict]:
        """List all Genie spaces"""
        result = self._make_request("GET", "/spaces")
        return result.get("spaces", []) if result else []

    def get_space(self, space_id: str) -> Optional[Dict]:
        """Get details of a specific space"""
        return self._make_request("GET", f"/spaces/{space_id}")

    # ========== CONVERSATIONS API ==========

    def start_conversation(self, space_id: str, content: str) -> Optional[Dict]:
        """Start a new conversation

        Returns:
            {
                "message_id": "...",
                "conversation_id": "...",
                "status": "EXECUTING_QUERY" | "COMPLETED" | "FAILED"
            }
        """
        return self._make_request(
            "POST",
            f"/spaces/{space_id}/start-conversation",
            json={"content": content}
        )

    def send_message(self, space_id: str, conversation_id: str, content: str) -> Optional[Dict]:
        """Send a follow-up message in existing conversation"""
        return self._make_request(
            "POST",
            f"/spaces/{space_id}/conversations/{conversation_id}/messages",
            json={"content": content}
        )

    def get_message(self, space_id: str, conversation_id: str, message_id: str) -> Optional[Dict]:
        """Get full message details including attachments

        This is the CRITICAL API we were missing!
        Returns complete message with:
        - attachments[].query.query (SQL)
        - attachments[].query.description
        - attachments[].query.statement_id
        - attachments[].id (attachment_id for query results)
        - row_count
        """
        return self._make_request(
            "GET",
            f"/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}"
        )

    def get_query_result(self, space_id: str, conversation_id: str,
                        message_id: str, attachment_id: str) -> Optional[Dict]:
        """Get actual query result data

        Returns:
            {
                "statement_response": {
                    "manifest": {
                        "schema": {"columns": [...]},
                        "total_row_count": 100,
                        "truncated": false
                    },
                    "result": {
                        "data_typed_array": [...]
                    }
                }
            }
        """
        return self._make_request(
            "GET",
            f"/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}/attachments/{attachment_id}/query-result"
        )

    def list_conversations(self, space_id: str) -> List[Dict]:
        """List conversations in a space (if API exists)"""
        # This API might not exist, try it
        result = self._make_request("GET", f"/spaces/{space_id}/conversations")
        if result and "conversations" in result:
            return result["conversations"]
        return []


# ========== HELPER FUNCTIONS ==========

def parse_query_result(result_data: Dict) -> Optional[pd.DataFrame]:
    """Parse query result into pandas DataFrame"""
    try:
        statement_response = result_data.get("statement_response", {})
        manifest = statement_response.get("manifest", {})
        result = statement_response.get("result", {})

        # Get column names
        columns = []
        schema = manifest.get("schema", {})
        if "columns" in schema:
            columns = [col.get("name", f"col_{i}") for i, col in enumerate(schema["columns"])]

        # Get data rows
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
            return df, manifest.get("total_row_count"), manifest.get("truncated", False)

        return None, 0, False

    except Exception as e:
        st.error(f"Error parsing query result: {e}")
        return None, 0, False


# ========== SESSION STATE ==========

def init_session_state():
    """Initialize session state variables"""
    if 'api_client' not in st.session_state:
        st.session_state.api_client = None
    if 'current_space_id' not in st.session_state:
        st.session_state.current_space_id = None
    if 'current_conversation_id' not in st.session_state:
        st.session_state.current_conversation_id = None
    if 'chat_history' not in st.session_state:
        st.session_state.chat_history = []
    if 'message_details' not in st.session_state:
        st.session_state.message_details = {}


# ========== UI COMPONENTS ==========

def render_spaces_tab(client: GenieAPIClient):
    """Render the Genie Spaces tab"""
    st.header("🗂️ Genie Spaces")

    if st.button("🔄 Refresh Spaces", key="refresh_spaces"):
        st.rerun()

    spaces = client.list_spaces()

    if not spaces:
        st.info("No Genie spaces found in this workspace.")
        return

    st.write(f"Found {len(spaces)} space(s)")

    # Display spaces in columns
    for space in spaces:
        with st.container():
            col1, col2 = st.columns([3, 1])

            with col1:
                st.subheader(f"📁 {space.get('name', 'Unnamed Space')}")
                if space.get('description'):
                    st.caption(space.get('description'))
                st.caption(f"Space ID: `{space.get('id', 'unknown')}`")

            with col2:
                space_id = space.get('id', 'unknown')
                if st.button("Select Space", key=f"select_{space_id}"):
                    st.session_state.current_space_id = space_id
                    st.session_state.current_conversation_id = None
                    st.session_state.chat_history = []
                    st.success(f"Selected: {space.get('name')}")
                    st.rerun()

            st.divider()


def render_conversations_tab(client: GenieAPIClient):
    """Render the Conversations tab"""
    if not st.session_state.current_space_id:
        st.warning("⚠️ Please select a Genie space first (go to Spaces tab)")
        return

    space_id = st.session_state.current_space_id

    # Show current space info
    space_info = client.get_space(space_id)
    if space_info:
        st.header(f"💬 Conversations in: {space_info.get('name', 'Unknown Space')}")
    else:
        st.header("💬 Conversations")

    st.caption(f"Space ID: `{space_id}`")

    # Try to list conversations (API may not exist)
    conversations = client.list_conversations(space_id)

    if conversations:
        st.write(f"Found {len(conversations)} conversation(s)")
        for conv in conversations:
            with st.container():
                col1, col2 = st.columns([3, 1])
                with col1:
                    st.write(f"**Conversation ID:** `{conv.get('id')}`")
                    st.caption(f"Created: {conv.get('created_timestamp', 'N/A')}")
                with col2:
                    if st.button("Load", key=f"load_{conv.get('id')}"):
                        st.session_state.current_conversation_id = conv.get('id')
                        st.success("Conversation loaded!")
                        st.rerun()
                st.divider()
    else:
        st.info("No conversations found. Start a new conversation in the Chat tab!")


def render_chat_tab(client: GenieAPIClient):
    """Render the main Chat tab"""
    if not st.session_state.current_space_id:
        st.warning("⚠️ Please select a Genie space first (go to Spaces tab)")
        return

    space_id = st.session_state.current_space_id

    # Show space info
    space_info = client.get_space(space_id)
    st.header(f"🧞 Chat with Genie: {space_info.get('name', 'Unknown') if space_info else 'Unknown'}")

    # Conversation status
    if st.session_state.current_conversation_id:
        st.success(f"✅ Active Conversation: `{st.session_state.current_conversation_id}`")
        if st.button("🔄 Start New Conversation"):
            st.session_state.current_conversation_id = None
            st.session_state.chat_history = []
            st.session_state.message_details = {}
            st.rerun()
    else:
        st.info("💡 Start a new conversation by asking a question below")

    st.divider()

    # Display chat history
    for idx, msg in enumerate(st.session_state.chat_history):
        with st.chat_message(msg.get("role", "user")):
            st.write(msg.get("content", ""))

            # If this is an assistant message with details, show additional info
            if msg.get("role") == "assistant" and msg.get("message_id"):
                message_id = msg.get("message_id")
                details = st.session_state.message_details.get(message_id, {})

                # Show query description
                if details.get("description"):
                    st.info(f"**Query Description:** {details.get('description')}")

                # Show SQL
                if details.get("sql"):
                    st.code(details.get("sql"), language="sql")

                # Button to fetch/show query results
                if details.get("attachment_id"):
                    result_key = f"result_{message_id}"

                    if result_key not in st.session_state:
                        if st.button(f"📊 Show Query Results", key=f"btn_result_{idx}"):
                            with st.spinner("Fetching query results..."):
                                result_data = client.get_query_result(
                                    space_id,
                                    st.session_state.current_conversation_id,
                                    message_id,
                                    details.get("attachment_id")
                                )

                                if result_data:
                                    df, total_rows, truncated = parse_query_result(result_data)
                                    st.session_state[result_key] = {
                                        "df": df,
                                        "total_rows": total_rows,
                                        "truncated": truncated
                                    }
                                    st.rerun()
                    else:
                        # Show cached results
                        cached = st.session_state[result_key]
                        df = cached.get("df")
                        total_rows = cached.get("total_rows", 0)
                        truncated = cached.get("truncated", False)

                        if df is not None:
                            # Pagination info
                            if total_rows > len(df) or truncated:
                                st.info(f"📊 Showing {len(df):,} of {total_rows:,} total rows" +
                                       (" (results truncated)" if truncated else ""))
                            else:
                                st.success(f"📊 Showing all {total_rows:,} rows")

                            # Display data
                            st.dataframe(df, use_container_width=True)
                        else:
                            st.warning("No data available to display")

    st.divider()

    # Chat input
    user_query = st.chat_input("Ask Genie a question...")

    if user_query:
        # Add user message to chat
        st.session_state.chat_history.append({
            "role": "user",
            "content": user_query
        })

        # Determine if this is a new conversation or follow-up
        if st.session_state.current_conversation_id:
            # Follow-up message
            with st.spinner("🧞 Genie is thinking..."):
                response = client.send_message(
                    space_id,
                    st.session_state.current_conversation_id,
                    user_query
                )
        else:
            # New conversation
            with st.spinner("🧞 Genie is thinking..."):
                response = client.start_conversation(space_id, user_query)

                if response and "conversation_id" in response:
                    st.session_state.current_conversation_id = response.get("conversation_id")

        # Process response
        if response:
            message_id = response.get("id") or response.get("message_id")
            conversation_id = st.session_state.current_conversation_id

            # CRITICAL: Fetch full message details
            with st.spinner("Fetching message details..."):
                message_details = client.get_message(space_id, conversation_id, message_id)

            if message_details:
                # Extract information
                attachments = message_details.get("attachments", [])

                assistant_response = "✅ Query processed successfully!\n\n"
                details = {}

                if attachments:
                    attachment = attachments[0]

                    # Get query info
                    query_info = attachment.get("query", {})
                    details["sql"] = query_info.get("query")
                    details["description"] = query_info.get("description")
                    details["statement_id"] = query_info.get("statement_id")
                    details["attachment_id"] = attachment.get("id")

                    # Check for text content
                    text_content = attachment.get("text", {})
                    if text_content and text_content.get("content"):
                        assistant_response = text_content.get("content", assistant_response)

                # Store details
                st.session_state.message_details[message_id] = details

                # Add assistant message to chat
                st.session_state.chat_history.append({
                    "role": "assistant",
                    "content": assistant_response,
                    "message_id": message_id
                })

                st.rerun()
            else:
                st.error("Failed to fetch message details")
        else:
            st.error("Failed to get response from Genie")


# ========== MAIN APP ==========

def main():
    """Main application"""
    init_session_state()

    # Sidebar - Configuration
    with st.sidebar:
        st.title("⚙️ Configuration")

        # Get credentials
        host = os.getenv("DATABRICKS_HOST", "")
        token = os.getenv("DATABRICKS_TOKEN", "")

        if not host or not token:
            st.error("❌ Missing credentials in .env file")
            st.stop()

        # Initialize client
        if st.session_state.api_client is None:
            st.session_state.api_client = GenieAPIClient(host, token)

        st.success("✅ Connected")

        if st.session_state.current_space_id:
            st.info(f"**Current Space:**\n`{st.session_state.current_space_id}`")

        st.divider()

        # Debug info
        with st.expander("🔧 Debug Info"):
            st.json({
                "host": host[:30] + "...",
                "space_id": st.session_state.current_space_id,
                "conversation_id": st.session_state.current_conversation_id,
                "chat_history_count": len(st.session_state.chat_history)
            })

    # Main tabs
    tab1, tab2, tab3 = st.tabs(["🗂️ Spaces", "💬 Conversations", "🧞 Chat"])

    client = st.session_state.api_client

    with tab1:
        render_spaces_tab(client)

    with tab2:
        render_conversations_tab(client)

    with tab3:
        render_chat_tab(client)


if __name__ == "__main__":
    main()
