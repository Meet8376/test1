import json

class Storage:
    FILE = "data/todos.json"

    def load(self):
        try:
            with open(self.FILE) as f:
                return json.load(f)
        except:
            return []

    def save(self, todos):
        with open(self.FILE, "w") as f:
            json.dump(todos, f)
