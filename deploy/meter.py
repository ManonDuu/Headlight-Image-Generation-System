"""Shared, fail-closed reservation ledger. Reserved USD is NOT provider billed USD."""
import hashlib,json,os,sqlite3,sys,uuid
from datetime import datetime,timezone
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

def config():
    p=Path(os.environ.get('BUDGET_CONFIG',str(Path(__file__).with_name('budget.json'))))
    c=json.loads(p.read_text());ZoneInfo(c['timezone'])
    for key in ('daily_limit_usd','monthly_limit_usd','per_call_limit_usd'):
        if not 0<Decimal(str(c[key]))<=100000:raise ValueError('invalid budget configuration')
    return c

def connect():
    p=Path(os.environ.get('USAGE_DB','/data/usage.sqlite3'));p.parent.mkdir(parents=True,exist_ok=True)
    db=sqlite3.connect(p,timeout=30);db.execute('PRAGMA journal_mode=WAL');db.execute('PRAGMA busy_timeout=30000')
    db.execute('''CREATE TABLE IF NOT EXISTS calls(id TEXT PRIMARY KEY,module TEXT,actor TEXT,model TEXT,request_hash TEXT,created_at TEXT,day TEXT,month TEXT,reserved_micro INTEGER,state TEXT,http_status INTEGER,usage_json TEXT,finished_at TEXT,estimated_micro INTEGER,billed_micro INTEGER)''')
    return db

def reserve(module,model,body):
    c=config();amount=int(Decimal(str(c['reserves_usd'][module]))*1000000)
    if amount>int(Decimal(str(c['per_call_limit_usd']))*1000000):raise RuntimeError('单次预算不足，未调用模型')
    now=datetime.now(ZoneInfo(c['timezone']));day=now.strftime('%Y-%m-%d');month=now.strftime('%Y-%m')
    db=connect()
    try:
        db.execute('BEGIN IMMEDIATE')
        for column,value,limit in [('day',day,c['daily_limit_usd']),('month',month,c['monthly_limit_usd'])]:
            used=db.execute(f'SELECT COALESCE(SUM(reserved_micro),0) FROM calls WHERE {column}=?',(value,)).fetchone()[0]
            if used+amount>int(Decimal(str(limit))*1000000):raise RuntimeError('系统日/月预留额度不足，未调用模型')
        ident=uuid.uuid4().hex
        db.execute('INSERT INTO calls(id,module,actor,model,request_hash,created_at,day,month,reserved_micro,state) VALUES(?,?,?,?,?,?,?,?,?,?)',(ident,module,'system-shared',model,hashlib.sha256(body).hexdigest(),now.isoformat(),day,month,amount,'reserved'))
        db.commit();return ident
    finally:db.close()

def finish(ident,status,raw):
    # Whitelist numeric metadata only: never store prompts, images, raw errors or keys.
    usage={};state='outcome-unknown'
    try:
        data=json.loads(raw);u=data.get('usageMetadata',{})
        for k in ('promptTokenCount','candidatesTokenCount','totalTokenCount','thoughtsTokenCount','cachedContentTokenCount','toolUsePromptTokenCount'):
            if type(u.get(k)) is int and u[k]>=0:usage[k]=u[k]
        state='response-received' if status==200 else 'http-error'
    except (ValueError,AttributeError,TypeError):pass
    if not status:state='outcome-unknown'
    with connect() as db:
        db.execute('UPDATE calls SET state=?,http_status=?,usage_json=?,finished_at=? WHERE id=?',(state,int(status or 0),json.dumps(usage),datetime.now(timezone.utc).isoformat(),ident))

def summary():
    with connect() as db:
        rows=db.execute('SELECT day,module,COUNT(*),SUM(reserved_micro),SUM(CASE WHEN state IN (\'reserved\',\'outcome-unknown\') THEN 1 ELSE 0 END) FROM calls GROUP BY day,module ORDER BY day DESC,module').fetchall()
    return {'currency':'USD','accounting':'conservative reservations; not actual provider charges','estimated_cost':None,'provider_billed_cost':None,'rows':[dict(zip(('day','module','calls','reserved_micro_usd','unknown_calls'),r)) for r in rows]}

def budget_status():
    c=config();now=datetime.now(ZoneInfo(c['timezone']));day=now.strftime('%Y-%m-%d');month=now.strftime('%Y-%m')
    with connect() as db:
        used=db.execute('SELECT COALESCE(SUM(reserved_micro),0) FROM calls WHERE day=?',(day,)).fetchone()[0]/1000000
        monthly=db.execute('SELECT COALESCE(SUM(reserved_micro),0) FROM calls WHERE month=?',(month,)).fetchone()[0]/1000000
    return {'day':day,'timezone':c['timezone'],'limitUSD':c['daily_limit_usd'],'reservedUSD':used,'remainingUSD':round(max(0,min(c['daily_limit_usd']-used,c['monthly_limit_usd']-monthly)),6),'monthlyLimitUSD':c['monthly_limit_usd'],'monthlyReservedUSD':monthly,'unlimited':False,'scope':'system-shared','accounting':'reservation-not-invoice'}

if __name__=='__main__':
    try:
        if sys.argv[1]=='reserve':
            d=json.load(sys.stdin);print(reserve(d['module'],d['model'],d['body'].encode()))
        elif sys.argv[1]=='finish':
            d=json.load(sys.stdin);finish(d['id'],d['status'],d.get('raw',''));print('ok')
        elif sys.argv[1]=='summary':print(json.dumps(summary(),ensure_ascii=False,indent=2))
        else:raise ValueError('unknown operation')
    except Exception:
        print('用量记录或系统预算检查失败；请管理员检查配置和数据磁盘。',file=sys.stderr);sys.exit(1)
