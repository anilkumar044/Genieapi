# Musing: a personal AI agent for iPhone

Musing is a SwiftUI app modeled on Meta's **Muse**. You tell it what you need in a chat, and it gets it done with
the apps on your iPhone. It always asks before taking an action.

- *“What's on my calendar tomorrow?”*: checks your calendar.
- *“Find a time for lunch with Sam next week and put it on my calendar”*: looks for free slots, then asks
  before adding the event.
- *“Remind me to call Mom at 6pm”*: adds a reminder after you approve.
- *“Email Priya that I'm running late”*: finds Priya in Contacts and opens a draft for you to review and send.
- *“Remember that I prefer morning meetings”*: saves a memory it uses in future chats.

## How it works

```
iPhone app (chat, approvals, on-device tools)  ──►  Musing backend on AWS  ──►  Claude on Amazon Bedrock
```

- **The thinking happens in the cloud.** Claude runs on Amazon Bedrock behind the backend in [`backend/`](backend/README.md).
  The phone never holds AWS credentials.
- **The actions happen on your phone.** Calendar, Reminders and Contacts are read and changed through iOS's own
  frameworks, with iOS permission prompts. Claude asks for a tool; the app runs it and sends back the result.
- **You stay in control.**
  - Reads (checking your calendar, reminders or contacts) run automatically.
  - Every action shows an approval card first: adding or completing things, opening links, drafting messages.
  - Emails and texts open in the system composer, and you press Send yourself.
- **Connectors** (Settings): turn each one Off, **Read only**, or **Read & act**.
- **Private by default.** Chats and memories are stored only on the iPhone. The server stores only your account
  and a daily usage count.

## Test it on your Mac (no Apple Developer account or AWS deployment needed)

You need Xcode 16+, Node.js 22+, and **either** AWS credentials with Amazon Bedrock access **or** a Claude API key.

1. **Start the local server** in Terminal:
   ```bash
   cd Musing/backend
   npm install
   npm run dev                          # uses your AWS login (aws configure / aws sso login)
   # or: ANTHROPIC_API_KEY=sk-ant-... npm run dev   (uses the Claude API directly)
   ```
   Leave it running. It prints `Musing dev server on http://localhost:8787`.
2. **Run the app**: open `Musing/Musing.xcodeproj`, choose an **iPhone 16** simulator, and press **⌘R**.
   Debug builds connect to `http://localhost:8787` automatically.
3. Send a message, tap **Agree and Continue**, then **Developer Sign-In (local server)**.
4. Try the suggestions. The Simulator has its own Calendar, Reminders and Contacts apps, so add a few
   events or contacts there to give Musing something to find.

Debug builds leave out the Sign in with Apple entitlement, so they sign with a free Apple ID (Personal Team).
To run on a **physical iPhone** against the dev server, set `localDevURLString` in `Musing/AI/AIConfig.swift`
to your Mac's address, e.g. `http://Your-Mac.local:8787/`, and make sure the phone and Mac are on the same Wi-Fi.

## Going live

1. Join the **Apple Developer Program**. Sign in with Apple needs it, and so does the App Store.
2. Deploy the backend to AWS: see [`backend/README.md`](backend/README.md).
3. Paste the deployed `ApiUrl` into `deployedURLString` in `Musing/AI/AIConfig.swift`.
4. In Xcode, set your Team and a unique bundle ID (the same one you deployed with). Release builds include Sign in with Apple.
   To test Sign in with Apple in a Debug build, add the capability under **Signing & Capabilities**.

### App Store notes

- **Name:** “Muse” is Meta's app. Keep your App Store name, icon and description clearly your own (guideline 4.1)
  and don't mention Muse or Meta in the listing.
- **Already handled in the app:**
  - A consent screen before anything is shared with the AI (5.1.2).
  - In-app account deletion that also revokes Sign in with Apple (5.1.1(v)).
  - A privacy manifest (`Musing/PrivacyInfo.xcprivacy`).
  - Permission prompts for Calendar, Reminders and Contacts (`Info.plist`).
  - No-encryption export flag (`ITSAppUsesNonExemptEncryption`).
- **In App Store Connect**, declare the data types from the privacy manifest: user ID, user content, and contacts, all
  used for app functionality. Reviewers will need a way in: give them a test account, or make sure Sign in with
  Apple works on your live backend.

## Project layout

```
Musing/
├── Musing.xcodeproj
├── Info.plist                    Permission descriptions, local-network access for the dev server
├── Musing/
│   ├── MusingApp.swift
│   ├── Agent/
│   │   ├── AgentController.swift The agent loop: call Claude → run tools → approvals → continue
│   │   ├── DeviceTools.swift     Calendar, Reminders, Contacts, email/text drafts, links (EventKit, Contacts, MessageUI)
│   │   ├── Connectors.swift      Connectors, access levels, tool catalog
│   │   ├── Conversation.swift    Chat storage (on device), tool outcomes
│   │   ├── MemoryStore.swift     Saved memories (on device)
│   │   └── JSONValue.swift       Keeps Claude's content blocks byte-for-byte for replay
│   ├── AI/                       Backend client, Sign in with Apple account, config, Keychain
│   ├── Views/                    Chat, approval cards, settings/connectors, history, setup
│   ├── Musing.entitlements       Sign in with Apple (Release builds)
│   └── PrivacyInfo.xcprivacy
└── backend/                      AWS CDK app: Lambda + DynamoDB + Claude on Amazon Bedrock, and the local dev server
```

## Not in this version yet

- **Gmail and Google Calendar connectors.** These need Google Cloud OAuth and Google's app verification. Gmail's
  restricted scopes also need a paid security assessment before a public launch.
- **Tasks that keep running after you close the app.** The tools run on the phone, so the agent works while the app
  is open. Background work would need server-side connectors and push notifications.
- **Web browsing and search.** Musing suggests links instead.
