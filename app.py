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


def initialize_session_state():
    """Initialize Streamlit session state"""
    if 'conversation_id' not in st.session_state:
        st.session_state.conversation_id = None
    if 'messages' not in st.session_state:
        st.session_state.messages = []
    if 'genie_client' not in st.session_state:
        st.session_state.genie_client = None


def format_genie_response(response: GenieMessage) -> str:
    """Format Genie response for display"""
    if not response:
        return "No response received from Genie."

    formatted_text = ""

    # Process attachments
    if response.attachments:
        for attachment in response.attachments:
            if attachment.text and attachment.text.content:
                formatted_text += attachment.text.content + "\n\n"

            # If there's a query, show it
            if attachment.query and attachment.query.query:
                formatted_text += "**Generated SQL:**\n```sql\n"
                formatted_text += attachment.query.query + "\n```\n\n"

            # If there's a query result, show it
            if attachment.query and attachment.query.result:
                result = attachment.query.result
                if result.row_count and result.row_count > 0:
                    formatted_text += f"**Query returned {result.row_count} rows**\n"

    return formatted_text if formatted_text else "Genie processed your query."


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
