# 🧞 Databricks Genie Chat Assistant - MVP

A simple Streamlit application that integrates with Databricks Genie API to enable natural language querying of your data.

## 🚀 Quick Start (2-Day Demo Ready)

### Prerequisites

- Python 3.8 or higher
- Access to a Databricks workspace
- A Databricks Genie Space (already created in your workspace)
- Databricks personal access token

### Step 1: Get Your Databricks Credentials

#### 1.1 Get Databricks Host
Your Databricks host URL looks like: `https://your-workspace.cloud.databricks.com`

#### 1.2 Create Personal Access Token
1. Log into your Databricks workspace
2. Click your username in the top right → **User Settings**
3. Go to **Developer** → **Access tokens**
4. Click **Generate new token**
5. Give it a name (e.g., "Genie Chat App") and set expiration
6. Copy the token (you won't see it again!)

#### 1.3 Find Your Genie Space ID
1. Open your Genie Space in Databricks
2. Look at the URL: `https://<workspace>/genie/rooms/<SPACE_ID>`
3. Copy the `<SPACE_ID>` (looks like: `01abc123def456gh789`)

### Step 2: Install & Configure

```bash
# Clone or download this repository
cd Genieapi

# Create a virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Create your .env file
cp .env.example .env

# Edit .env with your credentials
nano .env  # or use any text editor
```

Your `.env` file should look like:
```env
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=dapiXXXXXXXXXXXXXXXXXXXXXXXXXXXX
GENIE_SPACE_ID=01XXXXXXXXXXXXXXXXXXXXXXXXXX
```

### Step 3: Run the App

```bash
streamlit run app.py
```

The app will open in your browser at `http://localhost:8501`

## 🎯 Features

### ✅ Included in MVP
- 💬 Chat interface with conversation history
- 🧞 Natural language queries to Genie
- 📊 Display text responses and SQL queries
- 🔄 Start new conversations
- 🗑️ Clear chat history
- 💡 Example query suggestions
- ⚙️ Configuration sidebar

### ❌ Not Included (Future Enhancements)
- Multiple Genie space support
- Conversation persistence (database)
- Advanced data visualizations
- Export conversations
- Rate limiting
- User authentication
- Query history/favorites

## 📖 How to Use

1. **Start the app** - Run `streamlit run app.py`
2. **Ask a question** - Type your data question in natural language
3. **View the response** - Genie will analyze and respond with insights
4. **Continue the conversation** - Ask follow-up questions naturally
5. **Start fresh** - Click "New Conversation" for a different topic

### Example Queries

Try asking:
- "Show me the top 10 customers by revenue"
- "What were total sales last month?"
- "Show me trends over the last 6 months"
- "Which products have the highest margins?"
- "Compare revenue by region"

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│      Streamlit UI (app.py)          │
│  - Chat interface                    │
│  - Session state management          │
│  - Response formatting               │
└─────────────────┬───────────────────┘
                  │
                  ↓
┌─────────────────────────────────────┐
│    GenieClient (Python SDK)          │
│  - start_conversation()              │
│  - send_message()                    │
│  - get_space_info()                  │
└─────────────────┬───────────────────┘
                  │
                  ↓
┌─────────────────────────────────────┐
│   Databricks Genie API               │
│  - Natural language processing       │
│  - SQL generation                    │
│  - Query execution                   │
└─────────────────┬───────────────────┘
                  │
                  ↓
┌─────────────────────────────────────┐
│   Your Data (Unity Catalog)          │
└─────────────────────────────────────┘
```

## 🛠️ Troubleshooting

### "Configuration Missing" Error
- Make sure your `.env` file exists in the project root
- Verify all three variables are set: `DATABRICKS_HOST`, `DATABRICKS_TOKEN`, `GENIE_SPACE_ID`
- Check for extra spaces or quotes in the `.env` file

### "Failed to initialize Databricks client"
- Verify your `DATABRICKS_HOST` URL is correct (should include `https://`)
- Check that your token hasn't expired
- Ensure your token has proper permissions

### "Error starting conversation"
- Verify your `GENIE_SPACE_ID` is correct
- Make sure the Genie Space exists in your workspace
- Check that your token has access to the Genie Space

### Connection Issues
- Ensure you have network access to your Databricks workspace
- Check if there are any firewall/proxy restrictions
- Verify the workspace URL is accessible from your machine

### Slow Responses
- Genie API can take 10-60 seconds for complex queries (this is normal)
- The "Genie is thinking..." spinner shows processing is happening
- Complex queries or large datasets take longer

## 📁 Project Structure

```
Genieapi/
├── app.py                  # Main Streamlit application
├── requirements.txt        # Python dependencies
├── .env.example           # Environment template
├── .env                   # Your credentials (git-ignored)
├── .gitignore            # Git ignore rules
└── README.md             # This file
```

## 🔒 Security Notes

- **Never commit your `.env` file** - It contains sensitive credentials
- **Token security** - Treat your Databricks token like a password
- **Rotate tokens** - Regularly regenerate your access tokens
- **Workspace access** - Only users with workspace access can use this app
- **Data access** - Genie respects Unity Catalog permissions

## 🐛 Known Limitations

- **Rate Limits**: Databricks Genie API has rate limits (~5 queries/min/workspace in preview)
- **Timeout**: Long-running queries may timeout (default: 20 minutes)
- **Public Preview**: Genie API is in public preview and may have changes
- **No Persistence**: Chat history is lost when you close the browser
- **Single Space**: Only one Genie Space supported at a time

## 🚀 Next Steps (Post-Demo)

After your demo, consider adding:
1. **Multi-space support** - Switch between different Genie spaces
2. **Conversation history** - Save and load past conversations
3. **Data visualization** - Parse and display charts from responses
4. **Export functionality** - Download conversations or results
5. **Rate limiting** - Handle API rate limits gracefully
6. **User authentication** - Add login for multi-user deployments
7. **Error recovery** - Better error handling and retry logic
8. **Monitoring** - Add logging and usage analytics

## 📚 Resources

- [Databricks Genie API Documentation](https://docs.databricks.com/api/workspace/genie)
- [Databricks Python SDK](https://databricks-sdk-py.readthedocs.io/)
- [Streamlit Documentation](https://docs.streamlit.io/)
- [Genie Best Practices](https://docs.databricks.com/aws/en/genie/best-practices)

## 🤝 Contributing

This is an MVP for demo purposes. For production use:
- Add comprehensive error handling
- Implement proper logging
- Add unit and integration tests
- Set up CI/CD pipeline
- Add monitoring and alerting
- Follow security best practices

## 📝 License

This is a demo/MVP project. Use and modify as needed for your organization.

---

**Built with ❤️ using Databricks Genie API and Streamlit**

*For questions or issues, refer to the official Databricks documentation or your Databricks workspace admin.*
