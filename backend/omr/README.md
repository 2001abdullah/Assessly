# Assessly OMR adapter

The scanner is exposed through the Node API without the original OMR web
application, FastAPI server, or SQLite database.

## Scan an answer sheet

Send a `multipart/form-data` request to `POST /api/omr/scan`:

- `image` (required): JPG, PNG, or another image format supported by OpenCV.
- `template` (optional): the JSON template generated for the answer sheet. If
  omitted, `omr/templates/sample_template.json` is used.

Example:

```bash
curl -X POST http://localhost:5000/api/omr/scan \
  -F "image=@answer-sheet.jpg" \
  -F "template=@template.json"
```

The response is the engine's scan JSON plus `result_id`. The structured scan,
raw engine output, and detected answers are committed to PostgreSQL in one
transaction. Uploaded images and generated templates exist only in a temporary
directory and are removed after each request, including failed scans.

## Runtime

The Node process needs Python with the scanner dependencies installed. Set
`OMR_PYTHON` to the Python executable when `python` is not on `PATH`.
