def count_completed(todos):
    total = 0
    for todo in todos:
        if todo.get("done"):
            total += 1
