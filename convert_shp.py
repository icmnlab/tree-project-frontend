import shapefile
import json
import os

shp_path = r'c:\projects\tree_project\project_code\TW_county\COUNTY_MOI_1140318'
output_path = r'c:\projects\tree_project\project_code\backend\data\tw_county.geojson'

# Encoding from .cpg was UTF-8
with shapefile.Reader(shp_path, encoding='utf-8') as sf:
    features = []
    county_names = []
    for sr in sf.shapeRecords():
        # Get properties
        props = sr.record.as_dict()
        county_names.append(props.get('COUNTYNAME', ''))
        
        # Create GeoJSON feature
        feature = {
            "type": "Feature",
            "geometry": sr.shape.__geo_interface__,
            "properties": props
        }
        features.append(feature)

    collection = {
        "type": "FeatureCollection",
        "features": features
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(collection, f, separators=(',', ':'))

print(f"Encoding used: UTF-8")
print(f"Total feature count: {len(features)}")
print(f"File size: {os.path.getsize(output_path)} bytes")
print("COUNTYNAME values:")
print(', '.join(sorted(filter(None, county_names))))
