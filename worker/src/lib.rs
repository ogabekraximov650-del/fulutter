// src/lib.rs — Cloudflare Worker (Rust + WASM)
// worker crate v0.8.5 + worker-build (latest)

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use worker::*;

// ── CORS ─────────────────────────────────────────────────────

const CORS_ORIGIN: &str = "*";
const CORS_METHODS: &str = "GET, POST, PUT, DELETE, OPTIONS";
const CORS_HEADERS: &str = "Content-Type, Authorization";

fn add_cors(resp: &mut Response) -> &mut Response {
    let _ = resp.headers_mut().set("Access-Control-Allow-Origin", CORS_ORIGIN);
    let _ = resp.headers_mut().set("Access-Control-Allow-Methods", CORS_METHODS);
    let _ = resp.headers_mut().set("Access-Control-Allow-Headers", CORS_HEADERS);
    resp
}

fn json_resp(data: &Value, status: u16) -> Result<Response> {
    let mut resp = Response::from_json(data)?;
    *resp.status_code_mut() = status;
    add_cors(&mut resp);
    Ok(resp)
}

fn ok(v: Value) -> Result<Response> { json_resp(&v, 200) }
fn created(v: Value) -> Result<Response> { json_resp(&v, 201) }
fn err400(msg: &str) -> Result<Response> { json_resp(&json!({"error": msg}), 400) }
fn err404(msg: &str) -> Result<Response> { json_resp(&json!({"error": msg}), 404) }
fn err500(msg: &str) -> Result<Response> { json_resp(&json!({"error": msg}), 500) }

// ── Turso ─────────────────────────────────────────────────────

#[derive(Serialize, Deserialize, Debug, Clone)]
struct TursoArg {
    #[serde(rename = "type")]
    type_: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<String>,
}

impl TursoArg {
    fn null() -> Self { Self { type_: "null".into(), value: None } }
    fn text(v: &str) -> Self { Self { type_: "text".into(), value: Some(v.into()) } }
    fn int(v: i64) -> Self { Self { type_: "integer".into(), value: Some(v.to_string()) } }
}

fn row_to_obj(cols: &[Value], row: &[Value]) -> Value {
    let mut map = serde_json::Map::new();
    for (i, col) in cols.iter().enumerate() {
        let name = col["name"].as_str().unwrap_or("").to_string();
        let cell = &row[i];
        let t = cell["type"].as_str().unwrap_or("null");
        let val = if t == "null" {
            Value::Null
        } else if t == "integer" || t == "float" {
            let s = cell["value"].as_str().unwrap_or("0");
            s.parse::<i64>().map(|n| json!(n))
                .or_else(|_| s.parse::<f64>().map(|f| json!(f)))
                .unwrap_or(Value::Null)
        } else {
            json!(cell["value"].as_str().unwrap_or(""))
        };
        map.insert(name, val);
    }
    Value::Object(map)
}

async fn turso_exec(env: &Env, sql: &str, args: Vec<TursoArg>) -> Result<Value> {
    let url = env.secret("TURSO_URL")?.to_string();
    let token = env.secret("TURSO_TOKEN")?.to_string();

    let body = json!({
        "requests": [
            {"type": "execute", "stmt": {"sql": sql, "args": args}},
            {"type": "close"}
        ]
    });

    let mut req = Request::new_with_init(
        &format!("{url}/v2/pipeline"),
        RequestInit::new()
            .with_method(Method::Post)
            .with_headers({
                let mut h = Headers::new();
                h.set("Authorization", &format!("Bearer {token}"))?;
                h.set("Content-Type", "application/json")?;
                h
            })
            .with_body(Some(body.to_string().into())),
    )?;

    let mut resp = Fetch::Request(req).send().await?;
    let data: Value = resp.json().await?;

    let r = &data["results"][0];
    if r["type"] == "error" {
        return Err(Error::RustError(
            r["error"]["message"].as_str().unwrap_or("Turso xato").to_string()
        ));
    }
    Ok(r["response"]["result"].clone())
}

async fn turso_batch(env: &Env, stmts: &[(&str, Vec<TursoArg>)]) -> Result<()> {
    let url = env.secret("TURSO_URL")?.to_string();
    let token = env.secret("TURSO_TOKEN")?.to_string();

    let mut reqs: Vec<Value> = stmts.iter().map(|(sql, args)| {
        json!({"type": "execute", "stmt": {"sql": sql, "args": args}})
    }).collect();
    reqs.push(json!({"type": "close"}));

    let body = json!({"requests": reqs});
    let req = Request::new_with_init(
        &format!("{url}/v2/pipeline"),
        RequestInit::new()
            .with_method(Method::Post)
            .with_headers({
                let mut h = Headers::new();
                h.set("Authorization", &format!("Bearer {token}"))?;
                h.set("Content-Type", "application/json")?;
                h
            })
            .with_body(Some(body.to_string().into())),
    )?;
    Fetch::Request(req).send().await?;
    Ok(())
}

async fn init_db(env: &Env) {
    let _ = turso_batch(env, &[
        ("CREATE TABLE IF NOT EXISTS anime_db (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            photo_url TEXT NOT NULL,
            name TEXT NOT NULL UNIQUE,
            davlat TEXT NOT NULL,
            studiya TEXT NOT NULL,
            janri TEXT NOT NULL,
            tavsif TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )", vec![]),
        ("CREATE INDEX IF NOT EXISTS idx_name ON anime_db(name)", vec![]),
        ("CREATE INDEX IF NOT EXISTS idx_janri ON anime_db(janri)", vec![]),
    ]).await;
}

// ── B2 ────────────────────────────────────────────────────────

fn base64(input: &str) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let b = input.as_bytes();
    let mut out = String::new();
    let mut i = 0;
    while i < b.len() {
        let b0 = b[i] as u32;
        let b1 = if i+1 < b.len() { b[i+1] as u32 } else { 0 };
        let b2 = if i+2 < b.len() { b[i+2] as u32 } else { 0 };
        out.push(T[((b0>>2)&63) as usize] as char);
        out.push(T[(((b0<<4)|(b1>>4))&63) as usize] as char);
        out.push(if i+1 < b.len() { T[(((b1<<2)|(b2>>6))&63) as usize] as char } else { '=' });
        out.push(if i+2 < b.len() { T[(b2&63) as usize] as char } else { '=' });
        i += 3;
    }
    out
}

async fn b2_auth(env: &Env) -> Result<Value> {
    let cred = base64(&format!("{}:{}", env.secret("B2_KEY_ID")?, env.secret("B2_APPLICATION_KEY")?));
    let req = Request::new_with_init(
        "https://api.backblazeb2.com/b2api/v3/b2_authorize_account",
        RequestInit::new()
            .with_method(Method::Get)
            .with_headers({ let mut h = Headers::new(); h.set("Authorization", &format!("Basic {cred}"))?; h }),
    )?;
    let mut r = Fetch::Request(req).send().await?;
    let d: Value = r.json().await?;
    if r.status_code() != 200 {
        return Err(Error::RustError(format!("B2 auth xato: {}", d["message"].as_str().unwrap_or("unknown"))));
    }
    Ok(d)
}

async fn b2_bucket_id(auth: &Value, api_url: &str, auth_token: &str) -> Result<String> {
    let account_id = auth["accountId"].as_str().unwrap_or("");
    let req = Request::new_with_init(
        &format!("{api_url}/b2api/v3/b2_list_buckets?accountId={account_id}&bucketName=aniraxuz"),
        RequestInit::new()
            .with_method(Method::Get)
            .with_headers({ let mut h = Headers::new(); h.set("Authorization", auth_token)?; h }),
    )?;
    let mut r = Fetch::Request(req).send().await?;
    let d: Value = r.json().await?;
    Ok(d["buckets"][0]["bucketId"].as_str().unwrap_or("").to_string())
}

async fn b2_get_upload_url(env: &Env) -> Result<Value> {
    let auth = b2_auth(env).await?;
    let api_url = auth["apiInfo"]["storageApi"]["apiUrl"].as_str().unwrap_or("").to_string();
    let token = auth["authorizationToken"].as_str().unwrap_or("").to_string();
    let bucket_id = b2_bucket_id(&auth, &api_url, &token).await?;

    let body = json!({"bucketId": bucket_id});
    let req = Request::new_with_init(
        &format!("{api_url}/b2api/v3/b2_get_upload_url"),
        RequestInit::new()
            .with_method(Method::Post)
            .with_headers({ let mut h = Headers::new(); h.set("Authorization", &token)?; h.set("Content-Type", "application/json")?; h })
            .with_body(Some(body.to_string().into())),
    )?;
    let mut r = Fetch::Request(req).send().await?;
    Ok(r.json().await?)
}

async fn b2_proxy(env: &Env, file_name: &str) -> Result<Response> {
    let auth = b2_auth(env).await?;
    let dl_url = auth["apiInfo"]["storageApi"]["downloadUrl"].as_str().unwrap_or("").to_string();
    let token = auth["authorizationToken"].as_str().unwrap_or("").to_string();

    let url = format!("{dl_url}/file/aniraxuz/{file_name}");
    let req = Request::new_with_init(
        &url,
        RequestInit::new()
            .with_method(Method::Get)
            .with_headers({ let mut h = Headers::new(); h.set("Authorization", &token)?; h }),
    )?;
    let img = Fetch::Request(req).send().await?;

    if img.status_code() != 200 {
        let mut r = Response::empty()?;
        *r.status_code_mut() = 404;
        add_cors(&mut r);
        return Ok(r);
    }

    let ct = img.headers().get("Content-Type")?.unwrap_or_else(|| "image/jpeg".to_string());
    let bytes = img.bytes().await?;
    let mut resp = Response::from_bytes(bytes)?;
    add_cors(&mut resp);
    resp.headers_mut().set("Content-Type", &ct)?;
    resp.headers_mut().set("Cache-Control", "public, max-age=86400")?;
    Ok(resp)
}

async fn b2_delete(env: &Env, photo_url: &str) {
    let file_name = match photo_url.find("/api/image/") {
        Some(p) => &photo_url[p + 11..],
        None => return,
    };

    let auth = match b2_auth(env).await { Ok(a) => a, Err(_) => return };
    let api_url = auth["apiInfo"]["storageApi"]["apiUrl"].as_str().unwrap_or("").to_string();
    let token = auth["authorizationToken"].as_str().unwrap_or("").to_string();
    let account_id = auth["accountId"].as_str().unwrap_or("").to_string();
    let bucket_id = match b2_bucket_id(&auth, &api_url, &token).await { Ok(id) => id, Err(_) => return };

    // Fayl versiyasini topish
    let req = match Request::new_with_init(
        &format!("{api_url}/b2api/v3/b2_list_file_names?bucketId={bucket_id}&prefix={file_name}&maxFileCount=1"),
        RequestInit::new().with_method(Method::Get)
            .with_headers({ let mut h = Headers::new(); let _ = h.set("Authorization", &token); h }),
    ) { Ok(r) => r, Err(_) => return };
    let mut r = match Fetch::Request(req).send().await { Ok(r) => r, Err(_) => return };
    let d: Value = match r.json().await { Ok(d) => d, Err(_) => return };
    let file_id = match d["files"][0]["fileId"].as_str() { Some(id) => id.to_string(), None => return };

    // O'chirish
    let body = json!({"fileName": file_name, "fileId": file_id});
    let req2 = match Request::new_with_init(
        &format!("{api_url}/b2api/v3/b2_delete_file_version"),
        RequestInit::new().with_method(Method::Post)
            .with_headers({ let mut h = Headers::new(); let _ = h.set("Authorization", &token); let _ = h.set("Content-Type", "application/json"); h })
            .with_body(Some(body.to_string().into())),
    ) { Ok(r) => r, Err(_) => return };
    let _ = Fetch::Request(req2).send().await;
}

// ── Router ────────────────────────────────────────────────────

#[event(fetch)]
async fn main(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    let url = req.url()?;
    let path = url.path();
    let method = req.method();

    if method == Method::Options {
        let mut r = Response::empty()?;
        add_cors(&mut r);
        return Ok(r);
    }

    // GET /api/image/:filename
    if method == Method::Get {
        if let Some(fname) = path.strip_prefix("/api/image/") {
            return b2_proxy(&env, fname).await;
        }
    }

    init_db(&env).await;

    match (method.clone(), path.as_str()) {

        // GET /api/anime
        (Method::Get, "/api/anime") => {
            let res = turso_exec(&env, "SELECT * FROM anime_db ORDER BY id DESC LIMIT 100", vec![]).await?;
            let cols = res["cols"].as_array().cloned().unwrap_or_default();
            let rows = res["rows"].as_array().cloned().unwrap_or_default();
            ok(json!(rows.iter().map(|r| row_to_obj(&cols, r.as_array().unwrap_or(&vec![]))).collect::<Vec<_>>()))
        }

        // POST /api/anime
        (Method::Post, "/api/anime") => {
            let mut req = req;
            let b: Value = req.json().await?;
            let (pu, na, da, st, ja, ta) = (
                b["photo_url"].as_str().unwrap_or(""),
                b["name"].as_str().unwrap_or(""),
                b["davlat"].as_str().unwrap_or(""),
                b["studiya"].as_str().unwrap_or(""),
                b["janri"].as_str().unwrap_or(""),
                b["tavsif"].as_str().unwrap_or(""),
            );
            if [pu,na,da,st,ja,ta].iter().any(|s| s.is_empty()) {
                return err400("Hamma maydonlar kerak");
            }
            let res = turso_exec(&env,
                "INSERT INTO anime_db (photo_url,name,davlat,studiya,janri,tavsif) VALUES (?,?,?,?,?,?) RETURNING *",
                vec![TursoArg::text(pu), TursoArg::text(na), TursoArg::text(da), TursoArg::text(st), TursoArg::text(ja), TursoArg::text(ta)],
            ).await?;
            let cols = res["cols"].as_array().cloned().unwrap_or_default();
            let rows = res["rows"].as_array().cloned().unwrap_or_default();
            if rows.is_empty() { return err500("Qo'shib bo'lmadi"); }
            created(row_to_obj(&cols, rows[0].as_array().unwrap_or(&vec![])))
        }

        // POST /api/upload-token
        (Method::Post, "/api/upload-token") => {
            ok(b2_get_upload_url(&env).await?)
        }

        _ => {
            // GET /api/anime/janr/:janr
            if method == Method::Get {
                if let Some(janr) = path.strip_prefix("/api/anime/janr/") {
                    let res = turso_exec(&env, "SELECT * FROM anime_db WHERE janri = ? ORDER BY id DESC",
                        vec![TursoArg::text(janr)]).await?;
                    let cols = res["cols"].as_array().cloned().unwrap_or_default();
                    let rows = res["rows"].as_array().cloned().unwrap_or_default();
                    return ok(json!(rows.iter().map(|r| row_to_obj(&cols, r.as_array().unwrap_or(&vec![]))).collect::<Vec<_>>()));
                }
            }

            // /api/anime/:id
            if let Some(id_str) = path.strip_prefix("/api/anime/") {
                if let Ok(id) = id_str.parse::<i64>() {

                    // GET
                    if method == Method::Get {
                        let res = turso_exec(&env, "SELECT * FROM anime_db WHERE id = ?", vec![TursoArg::int(id)]).await?;
                        let cols = res["cols"].as_array().cloned().unwrap_or_default();
                        let rows = res["rows"].as_array().cloned().unwrap_or_default();
                        if rows.is_empty() { return err404("Anime topilmadi"); }
                        return ok(row_to_obj(&cols, rows[0].as_array().unwrap_or(&vec![])));
                    }

                    // PUT
                    if method == Method::Put {
                        let mut req = req;
                        let b: Value = req.json().await?;
                        let (pu, na, da, st, ja, ta) = (
                            b["photo_url"].as_str().unwrap_or("").to_string(),
                            b["name"].as_str().unwrap_or("").to_string(),
                            b["davlat"].as_str().unwrap_or("").to_string(),
                            b["studiya"].as_str().unwrap_or("").to_string(),
                            b["janri"].as_str().unwrap_or("").to_string(),
                            b["tavsif"].as_str().unwrap_or("").to_string(),
                        );
                        if [&pu,&na,&da,&st,&ja,&ta].iter().any(|s| s.is_empty()) {
                            return err400("Hamma maydonlar kerak");
                        }
                        let old = turso_exec(&env, "SELECT photo_url FROM anime_db WHERE id = ?", vec![TursoArg::int(id)]).await?;
                        let old_rows = old["rows"].as_array().cloned().unwrap_or_default();
                        if old_rows.is_empty() { return err404("Anime topilmadi"); }
                        let old_photo = {
                            let cols = old["cols"].as_array().cloned().unwrap_or_default();
                            row_to_obj(&cols, old_rows[0].as_array().unwrap_or(&vec![]))["photo_url"]
                                .as_str().unwrap_or("").to_string()
                        };
                        if !old_photo.is_empty() && old_photo != pu { b2_delete(&env, &old_photo).await; }
                        turso_exec(&env, "DELETE FROM anime_db WHERE id = ?", vec![TursoArg::int(id)]).await?;
                        let res = turso_exec(&env,
                            "INSERT INTO anime_db (photo_url,name,davlat,studiya,janri,tavsif) VALUES (?,?,?,?,?,?) RETURNING *",
                            vec![TursoArg::text(&pu), TursoArg::text(&na), TursoArg::text(&da), TursoArg::text(&st), TursoArg::text(&ja), TursoArg::text(&ta)],
                        ).await?;
                        let cols = res["cols"].as_array().cloned().unwrap_or_default();
                        let rows = res["rows"].as_array().cloned().unwrap_or_default();
                        if rows.is_empty() { return err500("Yangilashda xato"); }
                        return ok(row_to_obj(&cols, rows[0].as_array().unwrap_or(&vec![])));
                    }

                    // DELETE
                    if method == Method::Delete {
                        let old = turso_exec(&env, "SELECT photo_url FROM anime_db WHERE id = ?", vec![TursoArg::int(id)]).await?;
                        let old_rows = old["rows"].as_array().cloned().unwrap_or_default();
                        if old_rows.is_empty() { return err404("Anime topilmadi"); }
                        let old_photo = {
                            let cols = old["cols"].as_array().cloned().unwrap_or_default();
                            row_to_obj(&cols, old_rows[0].as_array().unwrap_or(&vec![]))["photo_url"]
                                .as_str().unwrap_or("").to_string()
                        };
                        if !old_photo.is_empty() { b2_delete(&env, &old_photo).await; }
                        turso_exec(&env, "DELETE FROM anime_db WHERE id = ?", vec![TursoArg::int(id)]).await?;
                        return ok(json!({"success": true}));
                    }
                }
            }

            err404("Not found")
        }
    }
}
