from todo import TodoManager

def test_add():
    manager = TodoManager()
    manager.add("Buy Milk")
    assert len(manager.todos) == 1

def test_complete():
    manager = TodoManager()
    manager.add("Buy Milk")
    manager.complete("Buy Milk")
    assert manager.todos[0]["done"]
