from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel

from adapters.postgres_repo import PostgresUserRepository
from api.deps import get_current_user, get_user_repo
from api.security import clear_session_cookie, create_session_token, set_session_cookie, verify_password
from domain.models import User

router = APIRouter()


class LoginIn(BaseModel):
    email: str
    password: str


class UserOut(BaseModel):
    id: str
    email: str
    display_name: str

    @classmethod
    def from_domain(cls, user: User) -> "UserOut":
        return cls(id=str(user.id), email=user.email, display_name=user.display_name)


class TokenOut(BaseModel):
    token: str
    user: UserOut


def _authenticate(payload: LoginIn, user_repo: PostgresUserRepository) -> User:
    user = user_repo.get_by_email(payload.email)
    if user is None or not user.is_active or user.password_hash is None:
        raise HTTPException(401, "Credenciales inválidas")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, "Credenciales inválidas")
    return user


@router.post("/login", response_model=UserOut)
def login(
    payload: LoginIn,
    response: Response,
    user_repo: PostgresUserRepository = Depends(get_user_repo),
):
    user = _authenticate(payload, user_repo)
    token = create_session_token(user.id)
    set_session_cookie(response, token)
    return UserOut.from_domain(user)


@router.post("/token", response_model=TokenOut)
def login_token(
    payload: LoginIn,
    user_repo: PostgresUserRepository = Depends(get_user_repo),
):
    user = _authenticate(payload, user_repo)
    return TokenOut(token=create_session_token(user.id), user=UserOut.from_domain(user))


@router.post("/logout")
def logout(response: Response):
    clear_session_cookie(response)
    return {"ok": True}


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return UserOut.from_domain(user)
