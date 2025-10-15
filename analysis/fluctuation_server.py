from flask import Flask, request, jsonify
from fluctuation_analysis_5m import run_detection

app = Flask(__name__)

@app.route('/calculate', methods=['GET'])
def calculate():
    data = run_detection()
    return jsonify(data)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001, debug=True)
