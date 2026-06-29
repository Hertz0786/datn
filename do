Setup Steps
1. Install AI Server (Whisper)
cd ai
pip install -r requirements.txt
python server.py
2. Install Backend Dependencies
cd be
npm install
npm run dev
3. Add New Environment Variables to Backend .env
# Email (Gmail SMTP)
GMAIL_USER=your-email@gmail.com
GMAIL_APP_PASSWORD=xxxx xxxx xxxx xxxx
# Google OAuth
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
# AI Server
AI_MODERATION_URL=http://localhost:8001
4. Create Google OAuth Client (for Google Sign-In)
Go to console.cloud.google.com
APIs & Services > Credentials > Create Credentials > OAuth client ID
Select Web application
Authorized redirect URIs: http://localhost:5000 (dev)
Copy Client ID into backend .env (GOOGLE_CLIENT_ID)
Copy Client ID into fe/.env (GOOGLE_CLIENT_ID)
5. Gmail App Password (for email)
Enable 2-Step Verification at myaccount.google.com
Go to Security > App passwords
Create a new app password (select app: Mail, device: Other)
Copy the 16-character App Password into backend .env (GMAIL_APP_PASSWORD)
6. Android: Get SHA-1 (if Google Sign-In on Android is needed)
cd fe/android
./gradlew signingReport
Find SHA1 in the output, add it to Firebase console (if applicable) or Google Cloud OAuth.
7. Android: Add Microphone Permission
Check that AndroidManifest.xml contains:

<uses-permission android:name="android.permission.RECORD_AUDIO"/>
If not present, add it.

If you encounter any errors while running, please let me know!
