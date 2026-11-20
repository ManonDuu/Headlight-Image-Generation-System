"""Bounded, evidence-linked variations within an approved composition family.

These are selected by the planner, not invented by the image model. Facts,
comparison ownership, four-weather coverage and set typography remain fixed.
"""
DETAILS = {
 'illumination': [
  ('See More Of The Road', 'Bring distant markings and roadside detail into view',
   'Emphasize long viewing depth and the distant lane markings; keep the required matched comparison geometry and all owner regions. Let the road recede deeply rather than enlarging the foreground.'),
  ('Make Roadside Detail Stand Out', 'Clearer road edges help reveal what lies ahead',
   'Emphasize the illuminated verge and roadside target detail. Give the verge enough scene area for texture and clear lateral coverage, while retaining distance and the selected comparison format.'),
 ],
 'beam': [
  ('Light Across The Lane', 'Broad coverage from the lane to its edges',
   'Within the selected camera format, emphasize lateral coverage: road and verge span most of the width. Keep the connected foreground and the natural soft perimeter visible.'),
  ('Keep The Road In View', 'Connected illumination reveals the road surface ahead',
   'Within the selected camera format, emphasize continuity and surface detail. Use visible pavement texture along a long connected path; keep lateral edges visible, not a detached bright patch.'),
 ],
 'protection': [
  ('Protection For Everyday Conditions', 'Built to resist water and dust',
   'For weather methods, use a richly colored rocky roadside environment and retain all four weather conditions. For macro, keep one coherent crop with droplets dominant and dust visible on the other side; no new parts or extra panels.'),
  ('Ready For Water And Dust', 'Protection for changing outdoor conditions',
   'For weather methods, use a green woodland environment and retain all four weather conditions. For macro, emphasize dust on visible exterior metal with a secondary droplet area, retaining the original geometry; no new parts or extra panels.'),
 ],
}

def detail(category, index):
    options=DETAILS.get(category,[])
    return options[index-1] if 1<=index<=len(options) else None
