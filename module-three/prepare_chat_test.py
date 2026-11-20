"""Export the exact stored image briefs for an in-chat image generation test.
Usage: python3 prepare_chat_test.py TASK_ID --output /path/to/test-packet.json
No model calls, credentials, re-planning, or prompt rewriting.
"""
import argparse
import json
from pathlib import Path
from core import Store
from design_rules import test_packet
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('task_id');parser.add_argument('--data',default=str(Path(__file__).parent/'data'));parser.add_argument('--output',required=True)
    args=parser.parse_args();record=Store(args.data).get(args.task_id)
    if 'setDesign' not in record['plan']: parser.error('旧任务尚无整套设计契约，请用当前版本重新保存该任务。')
    packet=test_packet(record['plan'])
    packet['assetFiles']=[{'id':a['id'],'path':str(Store(args.data)._path(record['id'])/a['file']),'sha256':a['sha256']} for a in record['assets']]
    path=Path(args.output);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(packet,ensure_ascii=False,indent=2))
    print(f'Exported {len(packet["images"])} single-image briefs. No generation requests sent.')
