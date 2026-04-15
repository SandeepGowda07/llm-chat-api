from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from groq import Groq
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(
    title="LLM Chat API",
    description="A cloud-native LLM Chat API deployed on Kubernetes",
    version="1.0.0"
)

client = Groq(api_key=os.getenv("GROQ_API_KEY"))
MODEL = "llama-3.3-70b-versatile"

class ChatRequest(BaseModel):
    prompt: str

class ChatResponse(BaseModel):
    response: str
    model: str

@app.get("/")
def root():
    return {
        "app": "LLM Chat API",
        "version": "1.0.0",
        "status": "running"
    }

@app.get("/health")
def health():
    return {"healthy": True}

@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest):
    if not request.prompt.strip():
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")
    
    try:
        completion = client.chat.completions.create(
            model=MODEL,
            messages=[
                {
                    "role": "system",
                    "content": "You are a helpful assistant. Keep responses concise and clear."
                },
                {
                    "role": "user",
                    "content": request.prompt
                }
            ],
            max_tokens=512,
        )
        return ChatResponse(
            response=completion.choices[0].message.content,
            model=MODEL
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))