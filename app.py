"""
Databricks Genie Chat - MVP
A simple Streamlit app to interact with Databricks Genie API
"""

import os
import time
from typing import Optional
from dotenv import load_dotenv
import streamlit as st
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.dashboards import GenieMessage

# Load environment variables
load_dotenv()

# Page configuration
st.set_page_config(
    page_title=os.getenv("APP_TITLE", "Genie Chat Assistant"),
    page_icon=os.getenv("APP_ICON", "🤖"),
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for better chat UI
st.markdown("""
<style>
    .stChatMessage {
        padding: 1rem;
        border-radius: 0.5rem;
        margin-bottom: 1rem;
    }
    .user-message {
        background-color: #e3f2fd;
    }
    .assistant-message {
        background-color: #f5f5f5;
    }
    .error-message {
        background-color: #ffebee;
        color: #c62828;
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 1rem 0;
    }
    .success-message {
        background-color: #e8f5e9;
        color: #2e7d32;
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 1rem 0;
    }
</style>
""", unsafe_allow_html=True)


class GenieClient:
    """Simple wrapper for Databricks Genie API"""

    def __init__(self, host: str, token: str, space_id: str):
        """Initialize the Genie client"""
        self.space_id = space_id
        try:
            self.client = WorkspaceClient(host=host, token=token)
            # Test connection
            self.client.current_user.me()
        except Exception as e:
            st.error(f"Failed to initialize Databricks client: {str(e)}")
            st.stop()

    def start_conversation(self, query: str) -> Optional[GenieMessage]:
        """Start a new conversation with Genie"""
        try:
            with st.spinner("🧞 Genie is thinking..."):
                response = self.client.genie.start_conversation_and_wait(
                    space_id=self.space_id,
                    content=query
                )
            return response
        except Exception as e:
            st.error(f"Error starting conversation: {str(e)}")
            return None

    def send_message(self, conversation_id: str, query: str) -> Optional[GenieMessage]:
        """Send a message in an existing conversation"""
        try:
            with st.spinner("🧞 Genie is thinking..."):
                response = self.client.genie.create_message_and_wait(
                    space_id=self.space_id,
                    conversation_id=conversation_id,
                    content=query
                )
            return response
        except Exception as e:
            st.error(f"Error sending message: {str(e)}")
            return None

    def get_space_info(self):
        """Get information about the Genie space"""
        try:
            space = self.client.genie.get_space(self.space_id)
            return space
        except Exception as e:
            st.warning(f"Could not fetch space info: {str(e)}")
            return None

    def list_spaces(self):
        """List all available Genie spaces"""
        try:
            spaces = list(self.client.genie.list_spaces())
            return spaces
        except Exception as e:
            st.warning(f"Could not list spaces: {str(e)}")
            return []

    def get_query_result(self, conversation_id: str, message_id: str, attachment_id: str):
        """Fetch actual query result data (the rows)"""
        try:
            result = self.client.genie.get_message_query_result(
                space_id=self.space_id,
                conversation_id=conversation_id,
                message_id=message_id,
                attachment_id=attachment_id
            )
            return result
        except Exception as e:
            st.warning(f"Could not fetch query results: {str(e)}")
            return None


def initialize_session_state():
    """Initialize Streamlit session state"""
    if 'conversation_id' not in st.session_state:
        st.session_state.conversation_id = None
    if 'messages' not in st.session_state:
        st.session_state.messages = []
    if 'genie_client' not in st.session_state:
        st.session_state.genie_client = None
    if 'debug_mode' not in st.session_state:
        st.session_state.debug_mode = False


def format_genie_response(response: GenieMessage, show_debug: bool = False) -> str:
    """Format Genie response for display with enhanced details"""
    if not response:
        return "No response received from Genie."

    formatted_text = ""

    # Process attachments
    if response.attachments:
        for i, attachment in enumerate(response.attachments, 1):
            # Debug mode - show raw attachment structure
            if show_debug:
                formatted_text += "**🔍 DEBUG - Raw Attachment Data:**\n"
                formatted_text += f"- Has text: {hasattr(attachment, 'text') and attachment.text is not None}\n"
                formatted_text += f"- Has query: {hasattr(attachment, 'query') and attachment.query is not None}\n"
                if hasattr(attachment.query, 'description'):
                    formatted_text += f"- Query description exists: {attachment.query.description is not None}\n"
                    if attachment.query.description:
                        formatted_text += f"- Query description value: '{attachment.query.description}'\n"
                formatted_text += "\n"

            # Natural language response
            if attachment.text and attachment.text.content:
                formatted_text += attachment.text.content + "\n\n"

            # Query information
            if attachment.query:
                # Query description - helpful context about what the SQL does
                # Note: Databricks UI doesn't show this, but it's useful!
                if hasattr(attachment.query, 'description') and attachment.query.description:
                    formatted_text += f"**Query Description:** {attachment.query.description}\n\n"

                # Generated SQL
                if attachment.query.query:
                    formatted_text += "**Generated SQL:**\n```sql\n"
                    formatted_text += attachment.query.query + "\n```\n\n"

            # Query result metadata
            if hasattr(attachment, 'query_result_metadata') and attachment.query_result_metadata:
                metadata = attachment.query_result_metadata
                if hasattr(metadata, 'row_count') and metadata.row_count is not None:
                    formatted_text += f"📊 **Results:** {metadata.row_count} row(s) returned"
                    if hasattr(metadata, 'truncated') and metadata.truncated:
                        formatted_text += " (truncated)"
                    formatted_text += "\n\n"

    return formatted_text if formatted_text else "Genie processed your query."


def display_query_results(genie_client, response: GenieMessage):
    """Fetch and display actual query result data as tables"""
    if not response or not response.attachments:
        return

    for attachment in response.attachments:
        # Check if there's a query with results to fetch
        if attachment.query and hasattr(attachment, 'id'):
            attachment_id = attachment.id

            # Fetch the actual data
            result = genie_client.get_query_result(
                conversation_id=response.conversation_id,
                message_id=response.id,
                attachment_id=attachment_id
            )

            if result and hasattr(result, 'statement_response'):
                statement_response = result.statement_response

                # Check if we have data
                if hasattr(statement_response, 'result') and statement_response.result:
                    result_data = statement_response.result

                    # Try to convert to pandas DataFrame for display
                    try:
                        import pandas as pd

                        # Get schema (column names)
                        columns = []
                        if hasattr(statement_response, 'manifest') and statement_response.manifest:
                            manifest = statement_response.manifest
                            if hasattr(manifest, 'schema') and manifest.schema:
                                schema = manifest.schema
                                if hasattr(schema, 'columns'):
                                    columns = [col.name for col in schema.columns]

                        # Get data rows
                        rows = []
                        if hasattr(result_data, 'data_typed_array'):
                            for row in result_data.data_typed_array:
                                if hasattr(row, 'values'):
                                    row_values = []
                                    for value in row.values:
                                        # Extract the actual value from typed data
                                        if hasattr(value, 'str'):
                                            row_values.append(value.str)
                                        elif hasattr(value, 'int'):
                                            row_values.append(value.int)
                                        elif hasattr(value, 'long'):
                                            row_values.append(value.long)
                                        elif hasattr(value, 'double'):
                                            row_values.append(value.double)
                                        elif hasattr(value, 'bool'):
                                            row_values.append(value.bool)
                                        else:
                                            row_values.append(str(value))
                                    rows.append(row_values)

                        # Create and display DataFrame
                        if rows and columns:
                            df = pd.DataFrame(rows, columns=columns)
                            st.dataframe(df, use_container_width=True)
                        elif rows:
                            # If no column names, just show the data
                            df = pd.DataFrame(rows)
                            st.dataframe(df, use_container_width=True)
                        else:
                            st.info("Query executed successfully but returned no data to display.")

                    except ImportError:
                        st.warning("pandas not installed. Install with: pip install pandas")
                    except Exception as e:
                        st.warning(f"Could not display data table: {str(e)}")
                        # Show raw result for debugging
                        with st.expander("View raw result data"):
                            st.json(result_data.as_dict() if hasattr(result_data, 'as_dict') else str(result_data))


def display_sidebar():
    """Display sidebar with configuration and info"""
    with st.sidebar:
        st.title("⚙️ Configuration")

        # Connection status
        if st.session_state.genie_client:
            st.success("✅ Connected to Databricks")

            # Get space info
            space_info = st.session_state.genie_client.get_space_info()
            if space_info:
                st.info(f"**Space:** {space_info.name if hasattr(space_info, 'name') else 'Unknown'}")
        else:
            st.error("❌ Not connected")

        st.divider()

        # Conversation controls
        st.subheader("💬 Conversation")

        if st.session_state.conversation_id:
            st.text(f"Active conversation")
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

        # Debug mode toggle
        st.subheader("🔧 Advanced")
        st.session_state.debug_mode = st.checkbox(
            "Debug Mode",
            value=st.session_state.debug_mode,
            help="Show raw API response data for troubleshooting"
        )

        st.divider()

        # Example queries
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

        # API Information
        with st.expander("🔌 API Info"):
            st.markdown("""
            **APIs Used:**

            This app uses the following Genie APIs:

            **Core Operations:**
            - `start_conversation_and_wait()` - Start new chat
            - `create_message_and_wait()` - Send questions
            - `get_message_query_result()` - Fetch result data
            - `get_space()` - Get space info

            **What you get in responses:**
            - ✅ Natural language answers
            - ✅ Generated SQL queries
            - ✅ Query descriptions (bonus: not shown in Databricks UI!)
            - ✅ Row count metadata
            - ✅ Actual data tables

            **Note:** The `_and_wait()` methods automatically
            handle polling and return complete responses with
            all data including SQL!

            See `GENIE_API_REFERENCE.md` for complete API docs.
            """)

        # About
        with st.expander("ℹ️ About"):
            st.markdown("""
            **Genie Chat Assistant**

            This app connects to Databricks Genie API to answer
            your data questions using natural language.

            **How to use:**
            1. Type your question in the chat
            2. Wait for Genie to analyze and respond
            3. Continue the conversation naturally

            **Tips:**
            - Be specific with your questions
            - Use example queries for inspiration
            - Start a new conversation for different topics
            """)

    return None


def main():
    """Main application"""

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

    # Display sidebar and get any example query clicked
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
            formatted_response = format_genie_response(response, show_debug=st.session_state.debug_mode)
            st.session_state.messages.append({
                "role": "assistant",
                "content": formatted_response
            })
            with st.chat_message("assistant"):
                st.markdown(formatted_response)

                # Fetch and display actual query result data
                display_query_results(genie_client, response)
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
