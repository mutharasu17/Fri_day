import os
import google.generativeai as genai

# Setup Gemini API
# Export your API key: export GEMINI_API_KEY='your-key-here'

api_key = os.getenv("GEMINI_API_KEY")

if not api_key:
    print("Error: GEMINI_API_KEY environment variable not set.")
    exit(1)

genai.configure(api_key=api_key)

def test_gemini():
    try:
        # Use the specific model found in the APIService
        model = genai.GenerativeModel('gemini-robotics-er-1.5-preview')
        response = model.generate_content("Hello Gemini, verify that you are working as the brain for OpenClaw.")
        print("Gemini Response:")
        print(response.text)
        return True
    except Exception as e:
        print(f"Failed to connect to Gemini: {e}")
        return False

if __name__ == "__main__":
    test_gemini()
