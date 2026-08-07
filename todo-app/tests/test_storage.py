from utils import count_completed

def test_count():
    todos = [
        {"done": True},
        {"done": False},
        {"done": True},
    ]
    assert count_completed(todos) == 2
